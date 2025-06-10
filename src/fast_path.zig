const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.HashMap;

// Binary lockfile format for ultra-fast parsing (inspired by pnpm)
// Format: [magic][version][gem_count][gems...]

pub const MAGIC = [4]u8{ 'G', 'R', 'L', 'K' }; // Gem Resolver Lock
pub const VERSION: u32 = 1;

pub const BinaryLockfile = struct {
    magic: [4]u8,
    version: u32,
    gem_count: u32,
    // Followed by packed gem entries
};

pub const PackedGem = packed struct {
    name_len: u16,
    version: u64, // Packed version struct
    dep_count: u16,
    source_type: u8,
    // Followed by: name bytes, then dep indices (u32 each)
};

// Content-addressable storage inspired by pnpm
pub const ContentStore = struct {
    base_path: []const u8,
    allocator: Allocator,
    
    pub fn init(allocator: Allocator, base_path: []const u8) ContentStore {
        return .{
            .allocator = allocator,
            .base_path = base_path,
        };
    }
    
    // Get gem path by content hash
    pub fn getGemPath(self: *ContentStore, name: []const u8, version: []const u8) ![]u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(name);
        hasher.update("@");
        hasher.update(version);
        
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // Store as: .gem-store/ab/cdef0123456789.../gem_files
        const hex = std.fmt.bytesToHex(hash, .lower);
        return std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/{s}-{s}", .{
            self.base_path,
            hex[0..2],
            hex[2..],
            name,
            version,
        });
    }
};

// Fast path resolver - skip resolution if lockfile unchanged
pub const FastPathResolver = struct {
    allocator: Allocator,
    lockfile_hash: ?[32]u8 = null,
    gemfile_hash: ?[32]u8 = null,
    
    pub fn init(allocator: Allocator) FastPathResolver {
        return .{ .allocator = allocator };
    }
    
    pub fn canUseFastPath(self: *FastPathResolver) !bool {
        // Check if Gemfile changed
        const gemfile_hash = try self.hashFile("Gemfile");
        // Try to open the lockfile
        const file = std.fs.cwd().openFile("Gemfile.lock.bin", .{}) catch return false;
        defer file.close();
        
        var header: BinaryLockfile = undefined;
        _ = try file.read(std.mem.asBytes(&header));
        
        if (!std.mem.eql(u8, &header.magic, &MAGIC)) return false;
        if (header.version != VERSION) return false;
        
        // Compare gemfile hash stored in lockfile
        var stored_hash: [32]u8 = undefined;
        _ = try file.read(&stored_hash);
        
        return std.mem.eql(u8, &gemfile_hash, &stored_hash);
    }
    
    fn hashFile(self: *FastPathResolver, path: []const u8) ![32]u8 {
        _ = self;
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var buf: [4096]u8 = undefined;
        
        while (true) {
            const bytes_read = try file.read(&buf);
            if (bytes_read == 0) break;
            hasher.update(buf[0..bytes_read]);
        }
        
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        return hash;
    }
};

// Parallel prefetcher with connection pooling
pub const ParallelPrefetcher = struct {
    allocator: Allocator,
    thread_pool: std.Thread.Pool,
    connection_pool: ConnectionPool,
    
    const ConnectionPool = struct {
        connections: [16]?std.net.Stream,
        mutex: std.Thread.Mutex,
        
        pub fn init() ConnectionPool {
            return .{
                .connections = [_]?std.net.Stream{null} ** 16,
                .mutex = .{},
            };
        }
        
        pub fn getConnection(self: *ConnectionPool) !std.net.Stream {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // Find available connection
            for (&self.connections) |*conn| {
                if (conn.*) |stream| {
                    conn.* = null;
                    return stream;
                }
            }
            
            // Create new connection
            return try std.net.tcpConnectToHost(std.heap.page_allocator, "rubygems.org", 443);
        }
        
        pub fn returnConnection(self: *ConnectionPool, stream: std.net.Stream) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            for (&self.connections) |*conn| {
                if (conn.* == null) {
                    conn.* = stream;
                    return;
                }
            }
            
            // Pool full, close connection
            stream.close();
        }
    };
    
    pub fn init(allocator: Allocator) !ParallelPrefetcher {
        var thread_pool = std.Thread.Pool{};
        try thread_pool.init(.{ .allocator = allocator });
        
        return .{
            .allocator = allocator,
            .thread_pool = thread_pool,
            .connection_pool = ConnectionPool.init(),
        };
    }
    
    pub fn deinit(self: *ParallelPrefetcher) void {
        self.thread_pool.deinit();
    }
    
    pub fn prefetchGems(self: *ParallelPrefetcher, gem_names: [][]const u8) !void {
        const Task = struct {
            prefetcher: *ParallelPrefetcher,
            gem_name: []const u8,
            
            fn run(task: @This()) void {
                // Simulate parallel gem metadata fetch
                const conn = task.prefetcher.connection_pool.getConnection() catch return;
                defer task.prefetcher.connection_pool.returnConnection(conn);
                
                // In real implementation: HTTP/2 multiplexed requests
                std.time.sleep(1_000_000); // 1ms simulated fetch
            }
        };
        
        var wait_group = std.Thread.WaitGroup{};
        
        for (gem_names) |name| {
            wait_group.start();
            try self.thread_pool.spawn(Task.run, .{
                .prefetcher = self,
                .gem_name = name,
            });
        }
        
        self.thread_pool.waitAndWork(&wait_group);
    }
};

// Memory-mapped lockfile for zero-copy parsing
pub const MmapLockfile = struct {
    data: []const u8,
    
    pub fn init(path: []const u8) !MmapLockfile {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        const stat = try file.stat();
        const data = try std.os.mmap(
            null,
            stat.size,
            std.os.PROT.READ,
            std.os.MAP.PRIVATE,
            file.handle,
            0,
        );
        
        return .{ .data = data };
    }
    
    pub fn deinit(self: *MmapLockfile) void {
        std.os.munmap(self.data);
    }
    
    pub fn parse(self: *MmapLockfile) !void {
        // Zero-copy parsing directly from mmap'd memory
        var offset: usize = 0;
        
        // Read header
        const header = @as(*const BinaryLockfile, @ptrCast(@alignCast(self.data.ptr)));
        offset += @sizeOf(BinaryLockfile);
        
        // Validate
        if (!std.mem.eql(u8, &header.magic, &MAGIC)) return error.InvalidFormat;
        
        // Parse gems without copying strings
        var i: u32 = 0;
        while (i < header.gem_count) : (i += 1) {
            const packed_gem = @as(*const PackedGem, @ptrCast(@alignCast(self.data.ptr + offset)));
            offset += @sizeOf(PackedGem);
            
            // Name is a slice into mmap'd memory - zero copy!
            _ = self.data[offset..offset + packed_gem.name_len];
            offset += packed_gem.name_len;
            
            // Skip dependencies for now
            offset += packed_gem.dep_count * @sizeOf(u32);
        }
    }
};