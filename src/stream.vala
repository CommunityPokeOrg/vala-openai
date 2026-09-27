/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * An open Server-Sent Events stream from `POST /chat/completions`.
     *
     * Obtained from {@link Client.chat_completion_stream} or
     * {@link Client.chat_completion_stream_async}. Pull successive
     * {@link ChatCompletionChunk}s with {@link next} / {@link next_async};
     * both return `null` once the stream has delivered `data: [DONE]` or the
     * connection ended. Dispose the stream to abort it early.
     */
    public class ChatCompletionStream : GLib.Object {
        private DataInputStream reader;
        private bool finished;

        /** Whether the stream has reached its terminator or EOF. */
        public bool is_finished {
            get { return finished; }
        }

        internal ChatCompletionStream(GLib.InputStream stream) {
            reader = new DataInputStream(stream);
            reader.set_newline_type(DataStreamNewlineType.ANY);
        }

        /**
         * Reads the next chunk, blocking until an event arrives or the
         * stream ends.
         *
         * @return the next chunk, or `null` at end of stream.
         */
        public ChatCompletionChunk? next(Cancellable? cancellable = null) throws Error {
            if (finished)
                return null;
            var data = new StringBuilder();
            try {
                while (true) {
                    size_t len;
                    string? line = reader.read_line_utf8(out len, cancellable);
                    if (line == null) {
                        finished = true;
                        break;
                    }
                    if (line == "") {
                        if (data.len > 0)
                            break;
                        continue;
                    }
                    accumulate_event_line(data, line);
                }
            } catch (GLib.Error e) {
                finished = true;
                throw error_from_io(e);
            }
            return decode_event(data);
        }

        /**
         * Reads the next chunk asynchronously.
         *
         * @return the next chunk, or `null` at end of stream.
         */
        public async ChatCompletionChunk? next_async(Cancellable? cancellable = null) throws Error {
            if (finished)
                return null;
            var data = new StringBuilder();
            try {
                while (true) {
                    string? line = yield reader.read_line_utf8_async(
                        Priority.DEFAULT, cancellable);
                    if (line == null) {
                        finished = true;
                        break;
                    }
                    if (line == "") {
                        if (data.len > 0)
                            break;
                        continue;
                    }
                    accumulate_event_line(data, line);
                }
            } catch (GLib.Error e) {
                finished = true;
                throw error_from_io(e);
            }
            return decode_event(data);
        }

        private void accumulate_event_line(StringBuilder data, string line) {
            if (!line.has_prefix("data:"))
                return; // event:/id:/retry:/comment lines carry no payload
            var payload = line.substring(5);
            if (payload.has_prefix(" "))
                payload = payload.substring(1);
            data.append(payload);
        }

        private ChatCompletionChunk? decode_event(StringBuilder data) throws Error {
            if (data.len == 0)
                return null;
            var payload = data.str.strip();
            if (payload == "[DONE]") {
                finished = true;
                return null;
            }
            return ChatCompletionChunk.from_data(payload);
        }

        /**
         * Marks the stream finished; the underlying connection is released
         * when the stream object is disposed.
         */
        public void close() {
            finished = true;
            try {
                reader.close();
            } catch (GLib.Error e) {
                // best effort; nothing useful to do on close failure
            }
        }
    }
}
