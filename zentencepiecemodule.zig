const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    // @cDefine("PY_LIMITED_API", "031200f0");
    @cInclude("Python.h");
});
const std = @import("std");
const root = @import("sentence_piece_zig_lib");

fn zentencepiece_load(self: [*c]c.PyObject, args: [*c]c.PyObject) callconv(.C) [*c]c.PyObject {
    _ = self;
    var command: [*:0]u8 = undefined;
    if (c.PyArg_ParseTuple(args, "s", &command) == 0)
        return null;
    const model_path = std.mem.sliceTo(command, 0); // Convert to []u8 until null terminator
    const obj = c.PyObject_CallObject(@ptrCast(TokenizerType), null) orelse return null;
    const tokenizer_obj: *TokenizerObject = @ptrCast(obj);
    const tokenizer = std.heap.c_allocator.create(root.Tokenizer) catch {
        c.Py_DECREF(obj);
        return null;
    };
    tokenizer.* = root.Tokenizer.init(std.heap.c_allocator, model_path) catch {
        c.Py_DECREF(obj);
        return null;
    };
    tokenizer_obj.tokenizer = tokenizer;
    return obj;
}

const TokenizerObject = extern struct {
    ob_base: c.PyObject,
    tokenizer: *root.Tokenizer, // need pointer to make this struct extern
};

fn TokenizerType_dealloc(self: *TokenizerObject) callconv(.C) void {
    std.debug.print("Deallocing", .{});
    c.Py_TYPE(@ptrCast(self)).*.tp_free.?(@ptrCast(self));
}

fn TokenizerType_free(self: *TokenizerObject) callconv(.C) void {
    std.debug.print("Freeing\n", .{});
    self.tokenizer.deinit();
    std.heap.c_allocator.destroy(self.tokenizer);
}

fn tokenize_method(self: ?*c.PyObject, arg: ?*c.PyObject) callconv(.C) ?*c.PyObject {
    if (self == null) {
        c.PyErr_SetString(c.PyExc_TypeError, "self is null. How come???");
        return null;
    }

    if (c.PyUnicode_Check(arg) == 0) {
        c.PyErr_SetString(c.PyExc_TypeError, "expected a str");
        return null;
    }
    var text_size: c.Py_ssize_t = undefined;
    const text_ptr = c.PyUnicode_AsUTF8AndSize(arg, @ptrCast(&text_size)).?;
    if (text_ptr == null) {
        return null; // PyUnicode_AsUTF8 already set an exception
    }
    const text = text_ptr[0..@intCast(text_size)];
    const tokenizer_object: *TokenizerObject = @ptrCast(self.?);
    const tokenizer = tokenizer_object.tokenizer;

    if (tokenizer.tokenize(std.heap.c_allocator, text)) |tokens| {
        defer tokens.deinit();
        const list_obj = c.PyList_New(@intCast(tokens.items.len));
        if (list_obj == null) return null;
        for (tokens.items, 0..) |token, i| {
            _ = c.PyList_SetItem(list_obj, @intCast(i), c.PyLong_FromLong(@intCast(token)));
        }
        return list_obj;
    } else |_| {
        c.PyErr_SetString(c.PyExc_TypeError, "Something went wrong while tokenizing!");
        return null;
    }
}

const TokenizerMethods = [_]c.PyMethodDef{
    .{
        .ml_name = "tokenize",
        .ml_meth = @ptrCast(&tokenize_method),
        .ml_flags = c.METH_O, // means: one argument (the text)
        .ml_doc = "Tokenize the given text",
    },
    .{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    },
};

var TokenizerType_slots = [_]c.PyType_Slot{
    .{ .slot = c.Py_tp_new, .pfunc = @constCast(@ptrCast(&c.PyType_GenericNew)) },
    .{ .slot = c.Py_tp_methods, .pfunc = @constCast(@ptrCast(&TokenizerMethods)) },
    .{ .slot = c.Py_tp_free, .pfunc = @constCast(@ptrCast(&TokenizerType_free)) },
    .{ .slot = c.Py_tp_dealloc, .pfunc = @constCast(@ptrCast(&TokenizerType_dealloc)) },
    .{ .slot = 0, .pfunc = null },
};

var TokenizerType_spec = c.PyType_Spec{
    .name = "zentencepiece.Tokenizer",
    .basicsize = @sizeOf(TokenizerObject),
    .itemsize = 0,
    .flags = c.Py_TPFLAGS_DEFAULT,
    .slots = @ptrCast(&TokenizerType_slots),
};

var TokenizerType: [*c]c.PyObject = null;

var zentencepicece_methods = [_]c.PyMethodDef{
    .{
        .ml_name = "load",
        .ml_meth = zentencepiece_load,
        .ml_flags = c.METH_VARARGS,
        .ml_doc = "Loads the tokenizer from SentencePiece model file.",
    },
    .{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    },
};

var zentencepiecemodule = c.PyModuleDef{
    .m_name = "zentencepiece",
    .m_doc = null,
    .m_methods = &zentencepicece_methods,
};

pub export fn PyInit_zentencepiece() ?*c.PyObject {
    const typ = c.PyType_FromSpec(&TokenizerType_spec);
    if (typ == null) return null;
    TokenizerType = @ptrCast(typ);

    const m = c.PyModule_Create(&zentencepiecemodule);
    if (m == null) return null;
    return m;
}
