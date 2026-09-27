/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * A model available through the API, as returned by `GET /models`.
     */
    public class ModelInfo : GLib.Object {
        /** Model identifier, e.g. `"gpt-4o"`. */
        public string id { get; private set; }
        /** Creation time as a Unix timestamp. */
        public int64 created { get; private set; }
        /** Owner organization, e.g. `"openai"`. */
        public string? owned_by { get; private set; }

        internal static ModelInfo from_json(Json.Object obj) {
            var m = new ModelInfo();
            m.id = json_opt_string(obj, "id") ?? "";
            m.created = json_opt_int(obj, "created");
            m.owned_by = json_opt_string(obj, "owned_by");
            return m;
        }
    }

    /**
     * The `GET /models` listing.
     */
    public class ModelList : GLib.Object {
        /** Available models. */
        public GenericArray<ModelInfo> data { get; private set; }

        /** Parses a listing from a decoded JSON object. */
        public static ModelList from_json(Json.Object obj) {
            var l = new ModelList();
            l.data = new GenericArray<ModelInfo>();
            var arr = json_opt_array(obj, "data");
            if (arr != null) {
                for (uint i = 0; i < arr.get_length(); i++) {
                    var el = arr.get_element(i);
                    if (el.get_node_type() == Json.NodeType.OBJECT)
                        l.data.add(ModelInfo.from_json(el.get_object()));
                }
            }
            return l;
        }

        /** Parses a listing from a raw JSON document. */
        public static ModelList from_data(string data) throws Error {
            return from_json(json_parse_object(data));
        }
    }
}
