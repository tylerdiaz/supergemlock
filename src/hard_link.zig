const std = @import("std");
const builtin = @import("builtin");

// Hard linking for gem deduplication (pnpm-style)
// Instead of copying gems, create hard links to save disk space

pub const HardLinkStore = struct {
    store_path: []const u8,
    allocator: std.mem.Allocator,
    stats: Stats,
    
    pub const Stats = struct {
        space_saved: u64 = 0,
        links_created: u64 = 0,
        gems_deduplicated: u64 = 0,
    };
    
    pub fn init(allocator: std.mem.Allocator, store_path: []const u8) !HardLinkStore {
        // Create store directory
        std.fs.cwd().makePath(store_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        
        return .{
            .allocator = allocator,
            .store_path = store_path,
            .stats = .{},
        };
    }
    
    // Link or copy gem to project
    pub fn linkGem(self: *HardLinkStore, content_hash: []const u8, target_path: []const u8) !void {
        const store_file = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.store_path, content_hash });
        defer self.allocator.free(store_file);
        
        // Try hard link first
        if (builtin.os.tag != .windows) {
            std.os.link(store_file, target_path, 0) catch |err| switch (err) {
                error.FileNotFound => {
                    // Store file doesn't exist, this is first use
                    try std.fs.cwd().rename(target_path, store_file);
                    try std.os.link(store_file, target_path, 0);
                },
                error.PathAlreadyExists => {
                    // Already linked, get stats for dedup tracking
                    const stat = try std.fs.cwd().statFile(store_file);
                    self.stats.space_saved += stat.size;
                    self.stats.gems_deduplicated += 1;
                    return;
                },
                else => {
                    // Fall back to symlink
                    try self.symlinkGem(store_file, target_path);
                },
            };
            
            self.stats.links_created += 1;
        } else {
            // Windows: use symlinks (requires admin) or copy
            self.symlinkGem(store_file, target_path) catch {
                try std.fs.cwd().copyFile(store_file, std.fs.cwd(), target_path, .{});
            };
        }
    }
    
    fn symlinkGem(self: *HardLinkStore, store_file: []const u8, target_path: []const u8) !void {
        // Calculate relative path from target to store
        const target_dir = std.fs.path.dirname(target_path) orelse ".";
        const rel_path = try std.fs.path.relative(self.allocator, target_dir, store_file);
        defer self.allocator.free(rel_path);
        
        try std.os.symlink(rel_path, target_path);
    }
    
    pub fn printStats(self: *HardLinkStore) void {
        const mb_saved = self.stats.space_saved / 1024 / 1024;
        std.debug.print("Hard link statistics:\n", .{});
        std.debug.print("  Space saved: {}MB\n", .{mb_saved});
        std.debug.print("  Links created: {}\n", .{self.stats.links_created});
        std.debug.print("  Gems deduplicated: {}\n", .{self.stats.gems_deduplicated});
    }
};

// Copy-on-write optimization for macOS APFS
pub const CowOptimizer = struct {
    pub fn cloneFile(src: []const u8, dst: []const u8) !void {
        if (builtin.os.tag == .macos) {
            // Use clonefile on APFS for instant, space-efficient copies
            const result = std.c.clonefile(src.ptr, dst.ptr, 0);
            if (result != 0) {
                return error.CloneFailed;
            }
        } else {
            // Regular copy on other systems
            try std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{});
        }
    }
};

// Atomic installation using rename
pub const AtomicInstaller = struct {
    temp_dir: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !AtomicInstaller {
        const temp_dir = try std.fmt.allocPrint(allocator, ".gem-install-{}", .{std.time.milliTimestamp()});
        try std.fs.cwd().makePath(temp_dir);
        
        return .{
            .allocator = allocator,
            .temp_dir = temp_dir,
        };
    }
    
    pub fn deinit(self: *AtomicInstaller) void {
        std.fs.cwd().deleteTree(self.temp_dir) catch {};
        self.allocator.free(self.temp_dir);
    }
    
    pub fn installAtomic(self: *AtomicInstaller, gems: []const GemToInstall) !void {
        // Install all gems to temp directory first
        for (gems) |gem| {
            const temp_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.temp_dir, gem.name });
            defer self.allocator.free(temp_path);
            
            // Extract/link gem to temp location
            try self.extractGem(gem, temp_path);
        }
        
        // Atomic rename of all gems
        for (gems) |gem| {
            const temp_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.temp_dir, gem.name });
            const final_path = try std.fmt.allocPrint(self.allocator, "vendor/bundle/{s}", .{gem.name});
            defer self.allocator.free(temp_path);
            defer self.allocator.free(final_path);
            
            // Atomic move
            try std.fs.cwd().rename(temp_path, final_path);
        }
    }
    
    fn extractGem(self: *AtomicInstaller, gem: GemToInstall, path: []const u8) !void {
        _ = self;
        _ = gem;
        _ = path;
        // Actual implementation would extract .gem file
    }
};

const GemToInstall = struct {
    name: []const u8,
    version: []const u8,
    content_hash: []const u8,
};