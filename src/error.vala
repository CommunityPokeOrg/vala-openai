/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * Error domain for all failures reported by the OpenAI client.
     *
     * Transport failures (DNS, TLS, timeouts, connection resets) are reported
     * as {@link Openai.Error.NETWORK}. HTTP responses outside the 2xx range are
     * mapped onto the more specific codes below; when the response body
     * contained an OpenAI error payload the parsed details are available from
     * {@link Client.last_error}.
     */
    public errordomain Error {
        /** A transport-level failure: DNS, TLS, connection reset or timeout. */
        NETWORK,
        /** Authentication failed (HTTP 401): the API key is missing or invalid. */
        AUTHENTICATION,
        /** The authenticated principal lacks permission (HTTP 403). */
        PERMISSION,
        /** The requested resource does not exist (HTTP 404). */
        NOT_FOUND,
        /** The request was rejected as malformed or invalid (HTTP 400/422). */
        INVALID_REQUEST,
        /** The request conflicted with the current resource state (HTTP 409). */
        CONFLICT,
        /** Rate limit or quota exhausted (HTTP 429). */
        RATE_LIMIT,
        /** The OpenAI service returned a 5xx status. */
        SERVER,
        /** A response body could not be decoded as the expected JSON shape. */
        PARSE,
        /** The operation was cancelled through a #GLib.Cancellable. */
        CANCELLED;
    }

    /**
     * Maps an HTTP status code onto an #Openai.Error value.
     */
    internal Error error_for_status(uint status, string message) {
        switch (status) {
            case 400:
            case 422:
                return new Error.INVALID_REQUEST("%s", message);
            case 401:
                return new Error.AUTHENTICATION("%s", message);
            case 403:
                return new Error.PERMISSION("%s", message);
            case 404:
                return new Error.NOT_FOUND("%s", message);
            case 409:
                return new Error.CONFLICT("%s", message);
            case 429:
                return new Error.RATE_LIMIT("%s", message);
            default:
                if (status >= 500)
                    return new Error.SERVER("%s", message);
                return new Error.INVALID_REQUEST("HTTP %u: %s", status, message);
        }
    }

    /**
     * Maps an arbitrary #GLib.Error raised by libsoup/GIO onto
     * #Openai.Error.NETWORK or #Openai.Error.CANCELLED.
     */
    internal Error error_from_io(GLib.Error e) {
        if (e.matches(GLib.IOError.quark(), GLib.IOError.CANCELLED))
            return new Error.CANCELLED("The operation was cancelled");
        return new Error.NETWORK("%s", e.message);
    }

    /**
     * A structured error object parsed from a failed OpenAI API response.
     *
     * OpenAI answers non-2xx responses with a JSON body containing an
     * `error` object with `message`, `type`, `param` and `code` members;
     * this class carries those fields to the caller.
     */
    public class ApiError : GLib.Object {
        /** The HTTP status code of the response. */
        public int status { get; private set; }
        /** Human-readable error description supplied by the API. */
        public string message { get; private set; }
        /** Error category reported by the API (e.g. `"invalid_request_error"`). */
        public string? error_type { get; private set; }
        /** Name of the offending request parameter, if any. */
        public string? param { get; private set; }
        /** Machine-readable error code (e.g. `"rate_limit_exceeded"`), if any. */
        public string? code { get; private set; }

        internal ApiError(int status, string message,
                          string? error_type = null,
                          string? param = null,
                          string? code = null) {
            this.status = status;
            this.message = message;
            this.error_type = error_type;
            this.param = param;
            this.code = code;
        }

        /**
         * Parses a response body into an #ApiError, tolerating malformed input.
         *
         * @param data   raw response body
         * @param status HTTP status code of the response
         * @return a populated #ApiError, or `null` when the body does not
         *         contain a recognizable error payload
         */
        public static ApiError? try_parse(string data, int status) {
            try {
                var obj = json_parse_object(data);
                var err_obj = json_opt_object(obj, "error");
                if (err_obj == null)
                    return null;
                return new ApiError(status,
                                    json_opt_string(err_obj, "message") ?? "Unknown API error",
                                    json_opt_string(err_obj, "type"),
                                    json_opt_string(err_obj, "param"),
                                    json_opt_string(err_obj, "code"));
            } catch (Error e) {
                return null;
            }
        }

        public string to_string() {
            var sb = new StringBuilder();
            sb.append_printf("Openai.ApiError(status=%d", status);
            if (error_type != null)
                sb.append_printf(", type=%s", error_type);
            if (code != null)
                sb.append_printf(", code=%s", code);
            sb.append_printf("): %s", message);
            return sb.str;
        }
    }
}
