/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 *
 * Minimal loopback HTTP/1.1 server used to exercise the client end-to-end
 * without touching the real OpenAI API. Responses are queued per test; the
 * most recent request is captured for assertions.
 */

/** A canned HTTP response handed out by {@link MockServer}. */
public class MockResponse {
    public int status;
    public HashTable<string, string> headers;
    public string body;
    public string content_type;

    public MockResponse(int status, string body,
                        string content_type = "application/json") {
        this.status = status;
        this.body = body;
        this.content_type = content_type;
        this.headers = new HashTable<string, string>(str_hash, str_equal);
    }

    public MockResponse header(string name, string value) {
        headers.set(name, value);
        return this;
    }
}

/** A request recorded by {@link MockServer}. */
public class RecordedRequest {
    public string method = "";
    public string path = "";
    public HashTable<string, string> headers =
        new HashTable<string, string>(str_hash, str_equal);
    public string body = "";
}

public class MockServer : GLib.Object {
    private SocketListener listener;
    private Thread<void*>? worker;
    private Queue<MockResponse> queue = new Queue<MockResponse>();
    private GenericArray<RecordedRequest> requests =
        new GenericArray<RecordedRequest>();
    private Mutex mutex = Mutex();
    private bool running;

    /** The loopback port the server is bound to. */
    public uint16 port { get; private set; }

    /** Number of requests received so far. */
    public int request_count {
        get {
            mutex.lock();
            var n = (int) requests.length;
            mutex.unlock();
            return n;
        }
    }

    /** Starts accepting connections on a background thread. */
    public void start() throws GLib.Error {
        listener = new SocketListener();
        port = listener.add_any_inet_port(null);
        running = true;
        worker = new Thread<void*>("mock-server", serve);
    }

    /** Queues a response; consumed FIFO, one per request. */
    public void push_response(MockResponse response) {
        mutex.lock();
        queue.push_tail(response);
        mutex.unlock();
    }

    /** The most recent request, or `null` if none arrived yet. */
    public RecordedRequest? last_request() {
        mutex.lock();
        var r = requests.length > 0 ? requests[requests.length - 1] : null;
        mutex.unlock();
        return r;
    }

    /** Stops the server and joins the worker thread. */
    public void stop() {
        running = false;
        // Wake the worker out of its blocking accept() so it can exit.
        try {
            new SocketClient().connect_to_host("127.0.0.1", port).close();
        } catch (GLib.Error e) {
            // listener already gone
        }
        if (worker != null) {
            worker.join();
            worker = null;
        }
        listener.close();
    }

    private void* serve() {
        while (running) {
            try {
                var conn = listener.accept(null, null);
                handle(conn);
                conn.close();
            } catch (GLib.Error e) {
                if (running)
                    warning("mock server: %s", e.message);
                break;
            }
        }
        return null;
    }

    private void handle(SocketConnection conn) throws GLib.Error {
        var input = new DataInputStream(conn.input_stream);
        input.set_newline_type(DataStreamNewlineType.ANY);

        var req = new RecordedRequest();
        size_t len;
        string? line = input.read_line_utf8(out len);
        if (line == null)
            return;

        var parts = line.split(" ");
        req.method = parts.length > 0 ? parts[0] : "";
        req.path = parts.length > 1 ? parts[1] : "/";

        int content_length = 0;
        bool expect_continue = false;
        while (true) {
            line = input.read_line_utf8(out len);
            if (line == null || line == "")
                break;
            var idx = line.index_of(":");
            if (idx < 0)
                continue;
            var name = line.substring(0, idx).strip();
            var value = line.substring(idx + 1).strip();
            req.headers.set(name, value);
            if (name.ascii_casecmp("content-length") == 0)
                content_length = int.parse(value);
            else if (name.ascii_casecmp("expect") == 0 &&
                     value.ascii_casecmp("100-continue") == 0)
                expect_continue = true;
        }

        if (expect_continue) {
            conn.output_stream.write_all(
                "HTTP/1.1 100 Continue\r\n\r\n".data, null, null);
            conn.output_stream.flush();
        }

        if (content_length > 0) {
            var buf = new uint8[content_length];
            size_t read = 0;
            input.read_all(buf, out read, null);
            req.body = ((string) buf).substring(0, (long) read);
        }

        mutex.lock();
        requests.add(req);
        var resp = queue.is_empty()
            ? new MockResponse(500,
                "{\"error\":{\"message\":\"mock: no response queued\"," +
                "\"type\":\"server_error\",\"code\":null,\"param\":null}}")
            : queue.pop_head();
        mutex.unlock();

        send_response(conn, resp);
    }

    private void send_response(SocketConnection conn, MockResponse resp)
            throws GLib.Error {
        var sb = new StringBuilder();
        sb.append_printf("HTTP/1.1 %d %s\r\n", resp.status, reason(resp.status));
        sb.append_printf("Content-Type: %s\r\n", resp.content_type);
        sb.append_printf("Content-Length: %ld\r\n", (long) resp.body.length);
        resp.headers.foreach(
            (k, v) => sb.append_printf("%s: %s\r\n", k, v));
        sb.append("Connection: close\r\n\r\n");
        conn.output_stream.write_all(sb.str.data, null, null);
        conn.output_stream.write_all(resp.body.data, null, null);
        conn.output_stream.flush();
    }

    private static string reason(int status) {
        switch (status) {
            case 200: return "OK";
            case 400: return "Bad Request";
            case 401: return "Unauthorized";
            case 403: return "Forbidden";
            case 404: return "Not Found";
            case 409: return "Conflict";
            case 422: return "Unprocessable Entity";
            case 429: return "Too Many Requests";
            case 500: return "Internal Server Error";
            case 502: return "Bad Gateway";
            case 503: return "Service Unavailable";
            default:  return "Status";
        }
    }
}
