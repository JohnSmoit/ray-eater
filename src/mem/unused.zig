//! Unused code
//! Mostly exists because I mistook a pool allocator
//! for a free list allocator and created part of an RBtree
//!
//! oops

const RBTree = struct {
    const NodeColor = enum(u8) {
        Red,
        Black,
    };

    ///NOTE: Probably best if this is 8-aligned
    pub const Node = struct {
        parent: *Node,
        left: *Node = null_node,
        right: *Node = null_node,

        color: NodeColor,
        buf: ?[]u8,

        pub inline fn isLeaf(self: Node) bool {
            return self.buf != null;
        }

        pub inline fn isNull(self: Node) bool {
            return self.left == null_node and self.right == null_node;
        }
    };

    const null_node = &Node{
        .parent = null_node,
        .left = null_node,
        .right = null_node,

        .color = .Black,
        .buf = null,
    };

    root: *Node,
    black_height: u32 = 1,

    fn partitionBuffer(buf: []u8) struct { *Node, []u8 } {
        assert(buf.len > @sizeOf(*Node));

        const node_space = @as(
            *Node,
            @ptrCast(@alignCast(buf[0..@sizeOf(*Node)].ptr)),
        );

        const buf_space = buf[@sizeOf(*Node)..];

        return .{ node_space, buf_space };
    }

    fn leftRotate() void {}

    fn rightRotate() void {}

    pub fn init(buf: []u8) RBTree {
        const root, const rest = partitionBuffer(buf);

        root.* = .{
            .parent = null_node,
            .color = .Black,
            .buf = rest,
        };

        return .{
            .root = root,
        };
    }

    pub fn insert(len: usize) void {}

    pub fn delete() void {}

    pub fn find() void {}
};



/// Red-Black Tree Tests
/// Makes a horribly unoptimized testing RB tree
/// by individually allocating and connecting nodes.
/// This function does not respect RBTree rules, and therefore must be
/// constructed correctly by hand for test cases.
const TreeTestBuilder = struct {
    const Direction = enum {
        Left,
        Right,
    };

    root: *RBTree.Node,
    allocator: Allocator,

    current_node: *RBTree.Node,

    pub fn initAlloc(allocator: Allocator, root_size: usize) TreeTestBuilder {
        const root: *RBTree.Node = allocator.create(RBTree.Node) orelse
            @panic("Allocation failure during test");

        root.parent = RBTree.null_node;
        root.left = RBTree.null_node;
        root.right = RBTree.null_node;
        root.color = .Black;

        return TreeTestBuilder{
            .root = root,
            .allocator = allocator,
            .current_node = root,
        };
    }

    /// deep-copy every node of an existing tree while preserving structure
    pub fn deepCopy(orig: *const RBTree, allocator: Allocator) TreeTestBuilder {}

    // creates a new child
    pub fn child(
        self: *TreeTestBuilder,
        dir: Direction,
        col: RBTree.NodeColor,
        size: usize,
    ) *TreeTestBuilder {}

    /// sets current node pointer to parent
    pub fn end(self: *TreeTestBuilder) *TreeTestBuilder {}

    pub fn build(self: *TreeTestBuilder) RBTree {}
};


fn expectTreeEqual(a: RBTree, b: RBTree, label: []const u8) !void {
}

test "insertion (all cases)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const scratch = arena.allocator();

    // Insertion case 1:
    const initial_tree_1 = TreeTestBuilder.initAlloc(scratch, 128).build();
    var final = TreeTestBuilder.deepCopy(&initial_tree_1).build();
    final.insert(64);

    const final_tree_1 = TreeTestBuilder.initAlloc(scratch, 128)
        .child(.Left, .Red, 64)
        .build();

    try expectTreeEqual(initial_tree_1, final_tree_1, "insertion case 1");

    // Insertion case 2 (single iteration):
    const initial_tree_2 = TreeTestBuilder.initAlloc(scratch, 128)
            .child(.Left, .Red, 64)
        .end()
            .child(.Right, .Red, 
    // Insertion case 2 & 3:
}

test "deletion (all cases)" {}

test "find (included)" {}

test "find (not included)" {}
