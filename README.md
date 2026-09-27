# vala-openai

A native [OpenAI API](https://platform.openai.com/docs/api-reference) client
library for Vala and the wider GObject ecosystem, built on
[libsoup 3](https://libsoup.gnome.org/) and
[json-glib](https://gnome.pages.gitlab.gnome.org/json-glib/).

## Features

- **Chat completions** — one-shot and streamed (SSE), with tool calling,
  JSON-mode `response_format`, seed, penalties, `stream_options` and the other
  request knobs, plus both blocking and `async` entry points.
- **Embeddings** — `POST /embeddings`, `float` and `base64` encodings.
- **Images** — `POST /images/generations`, URL and `b64_json` output,
  size/quality/style controls.
- **Models** — `GET /models` and `GET /models/{id}`.
- **Robust errors** — every failure lands in `Openai.Error`, mapped from HTTP
  status (401 → `AUTHENTICATION`, 429 → `RATE_LIMIT`, 5xx → `SERVER`, ...);
  structured API error bodies are exposed through `Client.last_error`.
- **Retries** — 429/5xx and transient transport failures are retried with
  exponential backoff honoring `Retry-After`, bounded by `max_retries`.
- **Typed models** — request/response types with `to_json`/`from_json`,
  nullable members only emitted when set.

## Requirements

- valac ≥ 0.56
- GLib/GIO ≥ 2.66
- libsoup-3.0
- json-glib-1.0
- Meson ≥ 0.56 + Ninja

Debian/Ubuntu: `sudo apt install valac meson ninja-build libglib2.0-dev
libsoup-3.0-dev libjson-glib-dev`

## Building

```sh
meson setup build
ninja -C build
```

Run the test suite (unit tests plus end-to-end client tests against an
in-process loopback HTTP server):

```sh
meson test -C build
```

Install:

```sh
sudo ninja -C build install
```

This installs `libopenai-1.0`, the `openai-1.0.vapi` VAPI (with a `.deps`
file), the `openai-1.0.h` C header and a `openai-1.0` pkg-config file, so the
library is consumable from Vala, C, and any GObject-introspection-friendly
toolchain.

## Usage

```vala
var client = new Openai.Client("sk-...");
// or: var client = Openai.Client.from_environment();

var request = new Openai.ChatCompletionRequest("gpt-4o");
request.add_system("You are terse.");
request.add_user("Say hi in three words.");
request.temperature = 0.7;

try {
    Openai.ChatCompletion reply = client.chat_completion(request);
    print("%s\n", reply.text);
    print("usage: %lld tokens\n", reply.usage.total_tokens);
} catch (Openai.Error e) {
    warning("%s", e.message);
}
```

Streaming:

```vala
var stream = client.chat_completion_stream(request);
Openai.ChatCompletionChunk? chunk;
while ((chunk = stream.next()) != null) {
    var delta = chunk.text_delta;
    if (delta != null)
        print(delta);
}
```

Async — every method has an `_async` twin:

```vala
var reply = yield client.chat_completion_async(request);
```

Compiling against the installed library:

```sh
valac --pkg openai-1.0 app.vala -o app
# or via pkg-config from C/meson projects: dependency('openai-1.0')
```

## API documentation

All public API carries valadoc comments. To render HTML docs:

```sh
meson setup build -Ddocs=true
ninja -C build docs   # output in build/docs/html/
```

## API surface

| Class | Purpose |
|-------|---------|
| `Openai.Client` | Transport, auth, retries; sync + async methods |
| `Openai.ChatCompletionRequest` | Chat request builder |
| `Openai.ChatMessage`, `ChatRole` | Conversation messages |
| `Openai.ChatCompletion`, `ChatChoice`, `CompletionUsage` | Response types |
| `Openai.ChatCompletionStream`, `ChatCompletionChunk`, `ChatDelta` | SSE streaming |
| `Openai.Tool`, `FunctionDefinition`, `ToolCall`, `FunctionCall` | Tool calling |
| `Openai.EmbeddingRequest`, `EmbeddingResponse`, `Embedding` | Embeddings |
| `Openai.ImageGenerationRequest`, `ImageGenerationResponse`, `GeneratedImage`, `ImageFormat` | Image generation |
| `Openai.ModelList`, `ModelInfo` | Model catalog |
| `Openai.Error`, `ApiError` | Error reporting |

## Notes and limitations

- Message `content` is handled as plain text; multipart content arrays
  (images, audio) are not yet modeled.
- Base64 embedding responses are decoded to `float[]` automatically
  (little-endian float32, per the API contract).
- Not covered yet: audio, files, fine-tuning, batch, assistants
  endpoints. The `Openai.Client` plumbing (`extra_headers`, `with_session`)
  is designed to make those incremental additions easy.

## License

MIT — see [LICENSE](LICENSE).
