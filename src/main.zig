const std = @import("std");

const Vector = struct {
    data: []f64,

    pub fn new(allocator: *std.mem.Allocator, size: usize) !Vector {
        return Vector{
            .data = try allocator.alloc(f64, size),
        };
    }

    pub fn deinit(self: *Vector, allocator: *std.mem.Allocator) void {
        allocator.free(self.data);
    }

    pub fn distance(self: *const Vector, other: *const Vector) f64 {
        var total: f64 = 0.0;
        var index: usize = 0;
        for (self.data) |value| {
            total += (value - other.data[index]) * (value - other.data[index]);
            index += 1;
        }
        return @sqrt(total);
    }
};

const db = struct {
    vectors: std.ArrayList(Vector),
    allocator: *std.mem.Allocator,

    pub fn new(allocator: *std.mem.Allocator) !db {
        const vec_list = std.ArrayList(Vector).init(allocator.*);
        return db{
            .vectors = vec_list,
            .allocator = allocator,
        };
    }

    pub fn addvec(self: *db, vector: Vector) !void {
        try self.vectors.append(vector);
    }

    pub fn nearestQuery(self: *db, query: *const Vector) ?*const Vector {
        var nearest: ?*const Vector = null;
        var min_dist = std.math.floatMax(f64);

        for (self.vectors.items) |vector| {
            const dist = query.distance(&vector);
            if (dist < min_dist) {
                min_dist = dist;
                nearest = &vector;
            }
        }

        return nearest;
    }

    pub fn cache_CSV(self: *db, filename: []const u8) !void {
        var file = try std.fs.cwd().openFile(filename, .{ .read = true });
        defer file.close();

        const csv_data = try file.readAllAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(csv_data);

        var reader = std.io.bufferedReader(std.io.reader(csv_data));
        var line: []const u8 = undefined;

        while (try reader.readUntilDelimiterOrEofAlloc(self.allocator, &line, '\n')) |line_content| {
            const tokens = std.mem.tokenize(line_content, ",");
            var vector = try Vector.new(self.allocator, tokens.len);
            defer vector.deinit(self.allocator);

            var index: usize = 0;
            for (tokens) |token| {
                vector.data[index] = try std.fmt.parseFloat(f64, token);
                index += 1;
            }
            try self.addvec(vector);
        }
    }

    pub fn deinit(self: *db) void {
        for (self.vectors.items) |vector| {
            vector.deinit(self.allocator);
        }
        self.vectors.deinit();
    }
};

const cli = struct {
    pub fn run(database: *db) !void {
        const args = std.os.argv;
        if (args.len < 2) {
            std.debug.print("Usage: vector_db <command> [args]\n", .{});
            return;
        }

        const cmd = std.mem.span(args[1]);
        if (std.mem.eql(u8, cmd, "add")) {
            if (args.len < 4) {
                std.debug.print("Usage: vector_db add <size> <elements...>\n", .{});
                return;
            }
            const sz = try std.fmt.parseInt(usize, std.mem.span(args[2]), 10);
            var vector = try Vector.new(database.allocator, sz);
            defer vector.deinit(database.allocator);

            if (args.len - 3 != sz) {
                std.debug.print("Error: Number of elements provided does not match the specified size.\n", .{});
                return;
            }

            var index: usize = 0;
            for (vector.data) |*value| {
                value.* = try std.fmt.parseFloat(f64, std.mem.span(args[3 + index]));
                index += 1;
            }
            try database.addvec(vector);
            std.debug.print("vector added.\n", .{});
        } else if (std.mem.eql(u8, cmd, "query")) {
            if (args.len < 4) {
                std.debug.print("Usage: vector_db query <size> <elements...>\n", .{});
                return;
            }
            const sz = try std.fmt.parseInt(usize, std.mem.span(args[2]), 10);
            var query_vector = try Vector.new(database.allocator, sz);
            defer query_vector.deinit(database.allocator);

            if (args.len - 3 != sz) {
                std.debug.print("Error: Number of elements provided does not match the specified size.\n", .{});
                return;
            }

            var index: usize = 0;
            for (query_vector.data) |*value| {
                value.* = try std.fmt.parseFloat(f64, std.mem.span(args[3 + index]));
                index += 1;
            }
            const res = database.nearestQuery(&query_vector);
            if (res) |nearest| {
                std.debug.print("the nearest vector found: {any}\n", .{nearest.*.data});
            } else {
                std.debug.print("no vectors are in the database.\n", .{});
            }
        } else if (std.mem.eql(u8, cmd, "csv")) {
            if (args.len < 3) {
                std.debug.print("Usage: vector_db csv <filename>\n", .{});
                return;
            }
            const filename = std.mem.span(args[2]);
            try database.cache_CSV(filename);
            std.debug.print("vectors loaded from .csv file.\n", .{});
        } else {
            std.debug.print("unknown command: {s}\n", .{cmd});
        }
    }
};

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var database = try db.new(&allocator);

    defer database.deinit();
    try cli.run(&database);
}
