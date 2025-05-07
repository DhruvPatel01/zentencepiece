pub fn Heap(t: comptime type) type {
    return struct { t };
}
