/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * Output format requested for generated images.
     */
    public enum ImageFormat {
        /** A temporary HTTPS URL (the API default). */
        URL,
        /** Base64-encoded image data. */
        B64_JSON;

        internal string to_wire() {
            return this == B64_JSON ? "b64_json" : "url";
        }
    }

    /**
     * Parameters for a `POST /images/generations` request.
     */
    public class ImageGenerationRequest : GLib.Object {
        /** Text description of the desired image. Required. */
        public string prompt { get; set; }
        /** Model identifier, e.g. `"dall-e-3"`; `null` uses the API default. */
        public string? model { get; set; }
        /** Number of images to generate; `null` uses the API default of 1. */
        public int64? n { get; set; }
        /** Output size, e.g. `"1024x1024"`, `"1792x1024"`, `"1024x1792"`. */
        public string? size { get; set; }
        /** `"standard"` or `"hd"` (DALL-E 3 only). */
        public string? quality { get; set; }
        /** `"vivid"` or `"natural"` (DALL-E 3 only). */
        public string? style { get; set; }
        /** Whether the response carries URLs or base64 data. */
        public ImageFormat format { get; set; default = ImageFormat.URL; }
        /** End-user identifier for abuse tracking. */
        public string? user { get; set; }

        public ImageGenerationRequest(string prompt) {
            this.prompt = prompt;
        }

        /** Serializes this request for `POST /images/generations`. */
        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("prompt", prompt);
            if (model != null)
                obj.set_string_member("model", model);
            if (n != null)
                obj.set_int_member("n", n);
            if (size != null)
                obj.set_string_member("size", size);
            if (quality != null)
                obj.set_string_member("quality", quality);
            if (style != null)
                obj.set_string_member("style", style);
            if (format == ImageFormat.B64_JSON)
                obj.set_string_member("response_format", format.to_wire());
            if (user != null)
                obj.set_string_member("user", user);
            return object_to_node(obj);
        }
    }

    /**
     * A single generated image.
     *
     * Exactly one of {@link url} and {@link b64_json} is populated, matching
     * the requested {@link ImageGenerationRequest.format}.
     */
    public class GeneratedImage : GLib.Object {
        /** Temporary URL of the image, when format is `url`. */
        public string? url { get; private set; }
        /** Base64-encoded image data, when format is `b64_json`. */
        public string? b64_json { get; private set; }
        /** The prompt actually used after API-side rewriting (DALL-E 3). */
        public string? revised_prompt { get; private set; }

        internal static GeneratedImage from_json(Json.Object obj) {
            var img = new GeneratedImage();
            img.url = json_opt_string(obj, "url");
            img.b64_json = json_opt_string(obj, "b64_json");
            img.revised_prompt = json_opt_string(obj, "revised_prompt");
            return img;
        }
    }

    /**
     * A complete `POST /images/generations` response.
     */
    public class ImageGenerationResponse : GLib.Object {
        /** Unix timestamp of when the images were generated. */
        public int64 created { get; private set; }
        /** The generated images, in request order. */
        public GenericArray<GeneratedImage> data { get; private set; }

        /** Parses a response from a decoded JSON object. */
        public static ImageGenerationResponse from_json(Json.Object obj) throws Error {
            var r = new ImageGenerationResponse();
            r.created = json_opt_int(obj, "created");
            r.data = new GenericArray<GeneratedImage>();
            var arr = json_opt_array(obj, "data");
            if (arr == null)
                throw new Error.PARSE("images response has no 'data' array");
            for (uint i = 0; i < arr.get_length(); i++) {
                var el = arr.get_element(i);
                if (el.get_node_type() == Json.NodeType.OBJECT)
                    r.data.add(GeneratedImage.from_json(el.get_object()));
            }
            return r;
        }

        /** Parses a response from a raw JSON document. */
        public static ImageGenerationResponse from_data(string data) throws Error {
            return from_json(json_parse_object(data));
        }
    }
}
