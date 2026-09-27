/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * Returns the string value of `member`, or `null` when it is absent, null,
     * or not a JSON string.
     */
    internal string? json_opt_string(Json.Object obj, string member) {
        if (!obj.has_member(member))
            return null;
        var node = obj.get_member(member);
        if (node.is_null() || node.get_node_type() != Json.NodeType.VALUE)
            return null;
        if (node.get_value_type() != typeof(string))
            return null;
        return node.get_string();
    }

    /**
     * Returns the integer value of `member`, or `fallback` when absent/null.
     */
    internal int64 json_opt_int(Json.Object obj, string member, int64 fallback = 0) {
        if (!obj.has_member(member))
            return fallback;
        var node = obj.get_member(member);
        if (node.is_null() || node.get_node_type() != Json.NodeType.VALUE)
            return fallback;
        return node.get_int();
    }

    /**
     * Returns the object stored at `member`, or `null` when absent/null or not
     * an object.
     */
    internal Json.Object? json_opt_object(Json.Object obj, string member) {
        if (!obj.has_member(member))
            return null;
        var node = obj.get_member(member);
        if (node.is_null() || node.get_node_type() != Json.NodeType.OBJECT)
            return null;
        return node.get_object();
    }

    /**
     * Returns the array stored at `member`, or `null` when absent/null or not
     * an array.
     */
    internal Json.Array? json_opt_array(Json.Object obj, string member) {
        if (!obj.has_member(member))
            return null;
        var node = obj.get_member(member);
        if (node.is_null() || node.get_node_type() != Json.NodeType.ARRAY)
            return null;
        return node.get_array();
    }

    /**
     * Parses `data` as a JSON document and returns its root object.
     *
     * @throws Error.PARSE when the body is not a JSON object.
     */
    internal Json.Object json_parse_object(string data) throws Error {
        var parser = new Json.Parser();
        try {
            parser.load_from_data(data, -1);
        } catch (GLib.Error e) {
            throw new Error.PARSE("Malformed JSON response: %s", e.message);
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT)
            throw new Error.PARSE("Expected a JSON object at the document root");
        return root.get_object();
    }

    /**
     * Serializes a #Json.Node to a compact string.
     */
    internal string node_to_string(Json.Node node) {
        var gen = new Json.Generator();
        gen.set_root(node);
        return gen.to_data(null);
    }

    /**
     * Wraps a #Json.Object in a #Json.Node for embedding or serialization.
     */
    internal Json.Node object_to_node(Json.Object obj) {
        var node = new Json.Node(Json.NodeType.OBJECT);
        node.set_object(obj);
        return node;
    }

    /**
     * Decodes a #GLib.Bytes into a string without assuming NUL termination.
     */
    internal string bytes_to_string(GLib.Bytes bytes) {
        var data = bytes.get_data();
        var sb = new StringBuilder();
        sb.append_len((string) data, (long) data.length);
        return sb.str;
    }
}
