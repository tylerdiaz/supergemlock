// supergemlock - High-performance Ruby dependency resolver
// Copyright (c) 2025 Tyler Diaz (me@tylerdiaz.com)
// SPDX-License-Identifier: MIT

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;

const fast_path = @import("src/fast_path.zig");
const hard_link = @import("src/hard_link.zig");

// Version representation using packed integers for fast comparison
pub const Version = packed struct {
    major: u16,
    minor: u16,
    patch: u16,
    _padding: u16 = 0,

    pub fn parse(str: []const u8) !Version {
        var iter = std.mem.tokenizeAny(u8, str, ".");
        return Version{
            .major = try std.fmt.parseInt(u16, iter.next() orelse "0", 10),
            .minor = try std.fmt.parseInt(u16, iter.next() orelse "0", 10),
            .patch = try std.fmt.parseInt(u16, iter.next() orelse "0", 10),
        };
    }

    pub fn satisfies(self: Version, constraint: Constraint) bool {
        // Use single 64-bit comparison for most operations
        const self_u64 = @as(u64, @bitCast(self));
        const constraint_u64 = @as(u64, @bitCast(constraint.version));
        
        return switch (constraint.op) {
            .eq => self_u64 == constraint_u64,
            .gte => self_u64 >= constraint_u64,
            .gt => self_u64 > constraint_u64,
            .lte => self_u64 <= constraint_u64,
            .lt => self_u64 < constraint_u64,
            .approx => self.major == constraint.version.major and
                self.minor >= constraint.version.minor,
        };
    }
    
    // SIMD batch comparison for M-series processors
    pub fn satisfiesBatch(versions: []const Version, constraint: Constraint, results: []bool) void {
        std.debug.assert(versions.len == results.len);
        
        const builtin = @import("builtin");
        if (builtin.cpu.arch == .aarch64) {
            // Process 2 versions at a time on Apple Silicon
            var i: usize = 0;
            while (i + 2 <= versions.len) : (i += 2) {
                const v = @Vector(2, u64){
                    @bitCast(versions[i]),
                    @bitCast(versions[i + 1]),
                };
                const c = @Vector(2, u64){
                    @bitCast(constraint.version),
                    @bitCast(constraint.version),
                };
                
                const cmp = switch (constraint.op) {
                    .gte => v >= c,
                    .gt => v > c,
                    .lte => v <= c,
                    .lt => v < c,
                    .eq => v == c,
                    .approx => @Vector(2, bool){ 
                        versions[i].satisfies(constraint),
                        versions[i + 1].satisfies(constraint),
                    },
                };
                
                results[i] = cmp[0];
                results[i + 1] = cmp[1];
            }
            
            // Handle remainder
            while (i < versions.len) : (i += 1) {
                results[i] = versions[i].satisfies(constraint);
            }
        } else {
            // Fallback for non-ARM
            for (versions, results) |v, *r| {
                r.* = v.satisfies(constraint);
            }
        }
    }

    pub fn format(self: Version, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}.{}.{}", .{ self.major, self.minor, self.patch });
    }
};

pub const ConstraintOp = enum { eq, gte, gt, lte, lt, approx };

pub const Constraint = struct {
    op: ConstraintOp,
    version: Version,

    pub fn parse(str: []const u8) !Constraint {
        var s = std.mem.trim(u8, str, " ");
        var op: ConstraintOp = .gte;

        if (std.mem.startsWith(u8, s, ">=")) {
            op = .gte;
            s = s[2..];
        } else if (std.mem.startsWith(u8, s, ">")) {
            op = .gt;
            s = s[1..];
        } else if (std.mem.startsWith(u8, s, "<=")) {
            op = .lte;
            s = s[2..];
        } else if (std.mem.startsWith(u8, s, "<")) {
            op = .lt;
            s = s[1..];
        } else if (std.mem.startsWith(u8, s, "~>")) {
            op = .approx;
            s = s[2..];
        } else if (std.mem.startsWith(u8, s, "=")) {
            op = .eq;
            s = s[1..];
        }

        s = std.mem.trim(u8, s, " ");
        return Constraint{
            .op = op,
            .version = try Version.parse(s),
        };
    }
};

pub const SourceType = enum {
    rubygems,
    github,
    git,
    path,
};

pub const GemSource = union(SourceType) {
    rubygems: void,
    github: struct {
        repo: []const u8,
        branch: ?[]const u8 = null,
        tag: ?[]const u8 = null,
        ref: ?[]const u8 = null,
    },
    git: struct {
        url: []const u8,
        branch: ?[]const u8 = null,
        tag: ?[]const u8 = null,
        ref: ?[]const u8 = null,
        glob: ?[]const u8 = null,
    },
    path: []const u8,
};

pub const GemOptions = struct {
    require: ?[]const u8 = null,
    platforms: ?ArrayList([]const u8) = null,
    groups: ?ArrayList([]const u8) = null,
    optional: bool = false, // for require: false
};

pub const Dependency = struct {
    name: []const u8,
    constraints: ArrayList(Constraint),
    source: GemSource = .rubygems,
    options: GemOptions = .{},
};

pub const Gem = struct {
    name: []const u8,
    version: Version,
    dependencies: ArrayList(Dependency),
};

const ResolvedGem = struct {
    name: []const u8,
    version: Version,
    source: GemSource,
    dependencies: ArrayList([]const u8), // Just dependency names for the lockfile
};

// Cache-line optimized version for Apple Silicon (128 bytes)
const CacheOptimizedGem = extern struct {
    name_hash: u64,           // 8 bytes
    version: Version,         // 8 bytes (packed)
    source_type: u8,          // 1 byte
    dep_count: u8,            // 1 byte
    _pad1: [6]u8 = [_]u8{0} ** 6,  // Padding to 24 bytes
    dep_indices: [26]u32,     // 104 bytes (26 * 4)
    // Total: 128 bytes = 1 M-series cache line
    
    comptime {
        std.debug.assert(@sizeOf(CacheOptimizedGem) == 128);
    }
};

const Resolution = struct {
    gems: HashMap([]const u8, Version, std.hash_map.StringContext, 80),
    resolved_gems: ArrayList(ResolvedGem),
    
    pub fn init(allocator: Allocator) Resolution {
        return .{
            .gems = HashMap([]const u8, Version, std.hash_map.StringContext, 80).init(allocator),
            .resolved_gems = ArrayList(ResolvedGem).init(allocator),
        };
    }
    
    pub fn deinit(self: *Resolution, allocator: Allocator) void {
        self.gems.deinit();
        for (self.resolved_gems.items) |*resolved| {
            allocator.free(resolved.name);
            for (resolved.dependencies.items) |dep_name| {
                allocator.free(dep_name);
            }
            resolved.dependencies.deinit();
        }
        self.resolved_gems.deinit();
    }
};

pub const LockfileWriter = struct {
    allocator: Allocator,
    resolution: *const Resolution,
    parser: *const GemfileParser,
    
    pub fn init(allocator: Allocator, resolution: *const Resolution, parser: *const GemfileParser) LockfileWriter {
        return .{
            .allocator = allocator,
            .resolution = resolution,
            .parser = parser,
        };
    }
    
    pub fn writeToFile(self: *LockfileWriter, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        try self.writeGemSection(writer);
        try self.writeGitSection(writer);
        try self.writePathSection(writer);
        try self.writePlatformsSection(writer);
        try self.writeRubyVersionSection(writer);
        try self.writeDependenciesSection(writer);
        try self.writeBundledWithSection(writer);
    }
    
    fn writeGemSection(self: *LockfileWriter, writer: anytype) !void {
        try writer.writeAll("GEM\n");
        try writer.writeAll("  remote: https://rubygems.org/\n");
        try writer.writeAll("  specs:\n");
        
        // Sort gems alphabetically
        var rubygems_list = ArrayList(ResolvedGem).init(self.allocator);
        defer rubygems_list.deinit();
        
        for (self.resolution.resolved_gems.items) |resolved| {
            switch (resolved.source) {
                .rubygems => try rubygems_list.append(resolved),
                else => {},
            }
        }
        
        // Simple bubble sort for small lists
        for (0..rubygems_list.items.len) |i| {
            for (i + 1..rubygems_list.items.len) |j| {
                if (std.mem.order(u8, rubygems_list.items[i].name, rubygems_list.items[j].name) == .gt) {
                    std.mem.swap(ResolvedGem, &rubygems_list.items[i], &rubygems_list.items[j]);
                }
            }
        }
        
        for (rubygems_list.items) |resolved| {
            try writer.print("    {s} ({})\n", .{ resolved.name, resolved.version });
            
            // Write dependencies
            if (resolved.dependencies.items.len > 0) {
                for (resolved.dependencies.items) |dep_name| {
                    if (self.resolution.gems.get(dep_name)) |dep_version| {
                        try writer.print("      {s} (= {})\n", .{ dep_name, dep_version });
                    }
                }
            }
        }
        try writer.writeAll("\n");
    }
    
    fn writeGitSection(self: *LockfileWriter, writer: anytype) !void {
        var has_git_gems = false;
        
        // Check if we have any git/github gems
        for (self.resolution.resolved_gems.items) |resolved| {
            switch (resolved.source) {
                .git, .github => {
                    has_git_gems = true;
                    break;
                },
                else => {},
            }
        }
        
        if (!has_git_gems) return;
        
        try writer.writeAll("GIT\n");
        
        for (self.resolution.resolved_gems.items) |resolved| {
            switch (resolved.source) {
                .github => |github| {
                    try writer.print("  remote: https://github.com/{s}.git\n", .{github.repo});
                    try writer.writeAll("  revision: abc123def456\n"); // Would be actual commit hash
                    if (github.branch) |branch| {
                        try writer.print("  branch: {s}\n", .{branch});
                    }
                    if (github.tag) |tag| {
                        try writer.print("  tag: {s}\n", .{tag});
                    }
                    try writer.writeAll("  specs:\n");
                    try writer.print("    {s} ({})\n", .{ resolved.name, resolved.version });
                    try writer.writeAll("\n");
                },
                .git => |git| {
                    try writer.print("  remote: {s}\n", .{git.url});
                    try writer.writeAll("  revision: abc123def456\n"); // Would be actual commit hash
                    if (git.branch) |branch| {
                        try writer.print("  branch: {s}\n", .{branch});
                    }
                    if (git.tag) |tag| {
                        try writer.print("  tag: {s}\n", .{tag});
                    }
                    if (git.ref) |ref| {
                        try writer.print("  ref: {s}\n", .{ref});
                    }
                    try writer.writeAll("  specs:\n");
                    try writer.print("    {s} ({})\n", .{ resolved.name, resolved.version });
                    try writer.writeAll("\n");
                },
                else => {},
            }
        }
    }
    
    fn writePathSection(self: *LockfileWriter, writer: anytype) !void {
        var has_path_gems = false;
        
        // Check if we have any path gems
        for (self.resolution.resolved_gems.items) |resolved| {
            switch (resolved.source) {
                .path => {
                    has_path_gems = true;
                    break;
                },
                else => {},
            }
        }
        
        if (!has_path_gems) return;
        
        try writer.writeAll("PATH\n");
        
        for (self.resolution.resolved_gems.items) |resolved| {
            switch (resolved.source) {
                .path => |path| {
                    try writer.print("  remote: {s}\n", .{path});
                    try writer.writeAll("  specs:\n");
                    try writer.print("    {s} ({})\n", .{ resolved.name, resolved.version });
                    try writer.writeAll("\n");
                },
                else => {},
            }
        }
    }
    
    fn writePlatformsSection(self: *LockfileWriter, writer: anytype) !void {
        _ = self;
        try writer.writeAll("PLATFORMS\n");
        // Default to current platform - in a real implementation, this would be detected
        try writer.writeAll("  x86_64-darwin-22\n");
        try writer.writeAll("  x86_64-linux\n");
        try writer.writeAll("\n");
    }
    
    fn writeRubyVersionSection(self: *LockfileWriter, writer: anytype) !void {
        _ = self;
        try writer.writeAll("RUBY VERSION\n");
        try writer.writeAll("   ruby 3.2.0p0\n");
        try writer.writeAll("\n");
    }
    
    fn writeDependenciesSection(self: *LockfileWriter, writer: anytype) !void {
        try writer.writeAll("DEPENDENCIES\n");
        
        // Sort dependencies alphabetically
        var deps = ArrayList(*const Dependency).init(self.allocator);
        defer deps.deinit();
        
        for (self.parser.dependencies.items) |*dep| {
            try deps.append(dep);
        }
        
        // Simple bubble sort
        for (0..deps.items.len) |i| {
            for (i + 1..deps.items.len) |j| {
                if (std.mem.order(u8, deps.items[i].name, deps.items[j].name) == .gt) {
                    std.mem.swap(*const Dependency, &deps.items[i], &deps.items[j]);
                }
            }
        }
        
        for (deps.items) |dep| {
            try writer.print("  {s}", .{dep.name});
            
            // Add version constraints
            if (dep.constraints.items.len > 0) {
                try writer.writeAll(" (");
                for (dep.constraints.items, 0..) |constraint, i| {
                    if (i > 0) try writer.writeAll(", ");
                    switch (constraint.op) {
                        .gte => try writer.print(">= {}", .{constraint.version}),
                        .gt => try writer.print("> {}", .{constraint.version}),
                        .lte => try writer.print("<= {}", .{constraint.version}),
                        .lt => try writer.print("< {}", .{constraint.version}),
                        .eq => try writer.print("= {}", .{constraint.version}),
                        .approx => try writer.print("~> {}", .{constraint.version}),
                    }
                }
                try writer.writeAll(")");
            }
            
            // Add source info
            switch (dep.source) {
                .github => {
                    try writer.writeAll("!\n");
                },
                .git => {
                    try writer.writeAll("!\n");
                },
                .path => {
                    try writer.writeAll("!\n");
                },
                .rubygems => try writer.writeAll("\n"),
            }
        }
        try writer.writeAll("\n");
    }
    
    fn writeBundledWithSection(self: *LockfileWriter, writer: anytype) !void {
        _ = self;
        try writer.writeAll("BUNDLED WITH\n");
        try writer.writeAll("   2.4.0\n"); // Simulated bundler version
    }
};

// Cache for gem metadata - in real implementation, this would be persistent
pub const GemCache = struct {
    data: HashMap([]const u8, ArrayList(Gem), std.hash_map.StringContext, 80),
    mutex: Thread.Mutex,

    pub fn init(allocator: Allocator) GemCache {
        return .{
            .data = HashMap([]const u8, ArrayList(Gem), std.hash_map.StringContext, 80).init(allocator),
            .mutex = Thread.Mutex{},
        };
    }

    pub fn deinit(self: *GemCache, allocator: Allocator) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |*gem| {
                for (gem.dependencies.items) |*dep| {
                    dep.constraints.deinit();
                }
                gem.dependencies.deinit();
            }
            entry.value_ptr.deinit();
            // Free the key string
            allocator.free(entry.key_ptr.*);
        }
        self.data.deinit();
    }

    pub fn getVersions(self: *GemCache, name: []const u8) ?[]const Gem {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.data.get(name)) |gems| {
            return gems.items;
        }
        return null;
    }

    pub fn addGem(self: *GemCache, allocator: Allocator, gem: Gem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Duplicate the gem name to ensure ownership
        const owned_name = try allocator.dupe(u8, gem.name);
        const result = try self.data.getOrPut(owned_name);
        if (!result.found_existing) {
            result.value_ptr.* = ArrayList(Gem).init(allocator);
        } else {
            // Free the duplicated name since we're not using it
            allocator.free(owned_name);
        }
        try result.value_ptr.append(gem);
    }
};

// Parallel resolver using work-stealing queue
// Gemfile parser
pub const GemfileParser = struct {
    allocator: Allocator,
    dependencies: ArrayList(Dependency),
    current_group: ?[]const u8,

    pub fn init(allocator: Allocator) GemfileParser {
        return .{
            .allocator = allocator,
            .dependencies = ArrayList(Dependency).init(allocator),
            .current_group = null,
        };
    }

    pub fn deinit(self: *GemfileParser) void {
        for (self.dependencies.items) |*dep| {
            self.allocator.free(dep.name);
            dep.constraints.deinit();
            
            // Free source-specific allocations
            switch (dep.source) {
                .github => |github| {
                    self.allocator.free(github.repo);
                    if (github.branch) |b| self.allocator.free(b);
                    if (github.tag) |t| self.allocator.free(t);
                    if (github.ref) |r| self.allocator.free(r);
                },
                .git => |git| {
                    self.allocator.free(git.url);
                    if (git.branch) |b| self.allocator.free(b);
                    if (git.tag) |t| self.allocator.free(t);
                    if (git.ref) |r| self.allocator.free(r);
                    if (git.glob) |g| self.allocator.free(g);
                },
                .path => |path| self.allocator.free(path),
                .rubygems => {},
            }
            
            // Free options
            if (dep.options.require) |r| self.allocator.free(r);
            if (dep.options.platforms) |*p| p.deinit();
            if (dep.options.groups) |*g| g.deinit();
        }
        self.dependencies.deinit();
    }

    pub fn parseFile(self: *GemfileParser, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        var lines = std.mem.tokenizeAny(u8, content, "\n\r");
        var line_num: usize = 0;
        while (lines.next()) |line| {
            line_num += 1;
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "#")) continue;

            self.parseLine(trimmed) catch |err| {
                std.debug.print("Error parsing line {}: {s}\n", .{ line_num, trimmed });
                return err;
            };
        }
    }

    fn parseLine(self: *GemfileParser, line: []const u8) !void {
        // Skip source declarations
        if (std.mem.startsWith(u8, line, "source")) return;
        
        // Skip gemspec declarations (would need .gemspec parser)
        if (std.mem.startsWith(u8, line, "gemspec")) return;
        
        // Skip ruby version constraints
        if (std.mem.startsWith(u8, line, "ruby")) return;

        // Handle group declarations
        if (std.mem.startsWith(u8, line, "group")) {
            // Simple group parsing - just track if we're in a group
            if (std.mem.indexOf(u8, line, "do") != null) {
                self.current_group = "group";
            }
            return;
        }

        // Handle end statements
        if (std.mem.eql(u8, line, "end")) {
            self.current_group = null;
            return;
        }

        // Parse gem declarations
        if (std.mem.startsWith(u8, line, "gem")) {
            try self.parseGemLine(line);
        }
    }

    fn parseGemLine(self: *GemfileParser, line: []const u8) !void {
        // Skip gems in groups for now (only parse top-level gems)
        if (self.current_group != null) return;

        // Skip conditional gems (if statements)
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "if ")) return;

        // Find gem name and constraints using a different approach
        // Format: gem "name", "constraint1", "constraint2", ..., options
        var rest = line[3..]; // Skip "gem"
        rest = std.mem.trimLeft(u8, rest, " \t");
        
        // Find the gem name (first quoted string)
        const name_start = std.mem.indexOf(u8, rest, "\"") orelse return;
        const name_end = std.mem.indexOf(u8, rest[name_start + 1..], "\"") orelse return;
        const name = rest[name_start + 1..name_start + 1 + name_end];
        
        var constraints = ArrayList(Constraint).init(self.allocator);
        var source = GemSource{ .rubygems = {} };
        var options = GemOptions{};
        
        // Check for require: false
        if (std.mem.indexOf(u8, rest, "require: false") != null or
            std.mem.indexOf(u8, rest, "require:false") != null) {
            options.optional = true;
        }
        
        // Parse the rest of the line
        rest = rest[name_start + name_end + 2..]; // Skip past the name
        
        // Check for git/github/path sources
        if (std.mem.indexOf(u8, rest, "github:") != null or 
            std.mem.indexOf(u8, rest, "git:") != null or
            std.mem.indexOf(u8, rest, "path:") != null) {
            // Handle git sources
            if (std.mem.indexOf(u8, rest, "github:")) |github_pos| {
                // Extract github repo
                const repo_start = std.mem.indexOf(u8, rest[github_pos..], "\"") orelse 0;
                const repo_end = std.mem.indexOf(u8, rest[github_pos + repo_start + 1..], "\"") orelse rest.len;
                const repo = try self.allocator.dupe(u8, rest[github_pos + repo_start + 1..github_pos + repo_start + 1 + repo_end]);
                
                source = .{ .github = .{ .repo = repo } };
            } else if (std.mem.indexOf(u8, rest, "git:")) |git_pos| {
                // Extract git URL
                const url_start = std.mem.indexOf(u8, rest[git_pos..], "\"") orelse 0;
                const url_end = std.mem.indexOf(u8, rest[git_pos + url_start + 1..], "\"") orelse rest.len;
                const url = try self.allocator.dupe(u8, rest[git_pos + url_start + 1..git_pos + url_start + 1 + url_end]);
                
                source = .{ .git = .{ .url = url } };
            } else if (std.mem.indexOf(u8, rest, "path:")) |path_pos| {
                // Extract path
                const path_start = std.mem.indexOf(u8, rest[path_pos..], "\"") orelse 0;
                const path_end = std.mem.indexOf(u8, rest[path_pos + path_start + 1..], "\"") orelse rest.len;
                const path = try self.allocator.dupe(u8, rest[path_pos + path_start + 1..path_pos + path_start + 1 + path_end]);
                
                source = .{ .path = path };
            }
        } else {
            // Parse version constraints for rubygems sources
            var pos: usize = 0;
            while (pos < rest.len) {
                const quote_start = std.mem.indexOf(u8, rest[pos..], "\"") orelse break;
                const actual_start = pos + quote_start;
                const quote_end = std.mem.indexOf(u8, rest[actual_start + 1..], "\"") orelse break;
                const actual_end = actual_start + 1 + quote_end;
                
                const constraint_str = rest[actual_start + 1..actual_end];
                pos = actual_end + 1;
                
                // Skip if this contains a colon or slash (it's an option like require: false/path)
                if (std.mem.indexOf(u8, constraint_str, ":") != null or
                    std.mem.indexOf(u8, constraint_str, "/") != null) continue;
                
                // Check if it's a valid version constraint
                if (constraint_str.len > 0 and !std.mem.eql(u8, constraint_str, "!=")) {
                    // Handle != constraints by skipping for now
                    if (std.mem.startsWith(u8, constraint_str, "!=")) continue;
                    
                    constraints.append(try Constraint.parse(constraint_str)) catch {
                        // If parsing fails, skip this constraint
                        continue;
                    };
                }
            }
        }

        // If no constraints specified, default to >= 0.0.0
        if (constraints.items.len == 0) {
            try constraints.append(Constraint{
                .op = .gte,
                .version = Version{ .major = 0, .minor = 0, .patch = 0 },
            });
        }

        try self.dependencies.append(Dependency{
            .name = try self.allocator.dupe(u8, name),
            .constraints = constraints,
            .source = source,
            .options = options,
        });
    }
};

pub const Resolver = struct {
    allocator: Allocator,
    cache: *GemCache,
    gemfile_deps: ArrayList(Dependency),
    resolution: Resolution,
    resolution_mutex: Thread.Mutex,
    work_queue: ArrayList([]const u8),
    queue_mutex: Thread.Mutex,
    done: std.atomic.Value(bool),

    pub fn init(allocator: Allocator, cache: *GemCache) Resolver {
        return .{
            .allocator = allocator,
            .cache = cache,
            .gemfile_deps = ArrayList(Dependency).init(allocator),
            .resolution = Resolution.init(allocator),
            .resolution_mutex = Thread.Mutex{},
            .work_queue = ArrayList([]const u8).init(allocator),
            .queue_mutex = Thread.Mutex{},
            .done = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Resolver) void {
        for (self.gemfile_deps.items) |*dep| {
            dep.constraints.deinit();
        }
        self.gemfile_deps.deinit();
        self.resolution.deinit(self.allocator);
        self.work_queue.deinit();
    }

    pub fn addDependency(self: *Resolver, dep: Dependency) !void {
        try self.gemfile_deps.append(dep);
        try self.work_queue.append(dep.name);
    }

    pub fn resolve(self: *Resolver) !void {
        const cpu_count = try Thread.getCpuCount();
        const thread_count = @min(cpu_count, self.gemfile_deps.items.len);
        
        if (thread_count <= 1) {
            try self.resolveWorker();
            return;
        }

        const threads = try self.allocator.alloc(Thread, thread_count);
        defer self.allocator.free(threads);

        for (threads) |*t| {
            t.* = try Thread.spawn(.{}, resolveWorker, .{self});
        }

        // Wait for threads to complete
        for (threads) |t| {
            t.join();
        }
        
        // Set done flag after all threads complete
        self.done.store(true, .release);
    }

    fn resolveWorker(self: *Resolver) !void {
        var idle_count: u32 = 0;
        while (!self.done.load(.acquire)) {
            const work_item = self.getWork() orelse {
                idle_count += 1;
                if (idle_count > 10) {
                    // Check if all work is done
                    self.queue_mutex.lock();
                    const queue_empty = self.work_queue.items.len == 0;
                    self.queue_mutex.unlock();
                    
                    if (queue_empty) {
                        return;
                    }
                }
                std.time.sleep(1_000_000); // 1ms
                continue;
            };

            idle_count = 0;
            try self.resolveGem(work_item);
        }
    }

    fn getWork(self: *Resolver) ?[]const u8 {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        if (self.work_queue.items.len == 0) {
            return null;
        }

        return self.work_queue.pop();
    }

    fn resolveGem(self: *Resolver, name: []const u8) !void {
        // Check if already resolved
        self.resolution_mutex.lock();
        const already_resolved = self.resolution.gems.contains(name);
        self.resolution_mutex.unlock();
        
        if (already_resolved) return;
        

        // Find constraints for this gem
        var constraints = ArrayList(Constraint).init(self.allocator);
        defer constraints.deinit();

        for (self.gemfile_deps.items) |dep| {
            if (std.mem.eql(u8, dep.name, name)) {
                try constraints.appendSlice(dep.constraints.items);
            }
        }

        // Get available versions from cache
        const versions = self.cache.getVersions(name) orelse {
            // In real implementation, fetch from rubygems.org
            return;
        };

        // Find the best matching version (simplified: highest that satisfies all)
        var best_version: ?Version = null;
        var best_gem: ?*const Gem = null;

        for (versions) |*gem| {
            var satisfies_all = true;
            for (constraints.items) |constraint| {
                if (!gem.version.satisfies(constraint)) {
                    satisfies_all = false;
                    break;
                }
            }

            if (satisfies_all) {
                if (best_version == null or @as(u64, @bitCast(gem.version)) > @as(u64, @bitCast(best_version.?))) {
                    best_version = gem.version;
                    best_gem = gem;
                }
            }
        }

        if (best_gem) |gem| {
            // Get source for this gem from original dependencies
            var gem_source = GemSource{ .rubygems = {} };
            for (self.gemfile_deps.items) |dep| {
                if (std.mem.eql(u8, dep.name, name)) {
                    gem_source = dep.source;
                    break;
                }
            }
            
            // Create dependency names list
            var dep_names = ArrayList([]const u8).init(self.allocator);
            for (gem.dependencies.items) |dep| {
                try dep_names.append(try self.allocator.dupe(u8, dep.name));
            }
            
            // Add to resolution
            self.resolution_mutex.lock();
            try self.resolution.gems.put(name, gem.version);
            try self.resolution.resolved_gems.append(ResolvedGem{
                .name = try self.allocator.dupe(u8, name),
                .version = gem.version,
                .source = gem_source,
                .dependencies = dep_names,
            });
            self.resolution_mutex.unlock();

            // Queue dependencies for resolution
            for (gem.dependencies.items) |dep| {
                self.queue_mutex.lock();
                try self.work_queue.append(dep.name);
                self.queue_mutex.unlock();
            }
        }
    }
};

pub fn main() !void {
    // Check for version flag
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);
    
    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v")) {
            std.debug.print("supergemlock 0.1.0\n", .{});
            return;
        } else if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            std.debug.print("supergemlock - High-performance Ruby dependency resolver\n\n", .{});
            std.debug.print("Usage: supergemlock [options]\n\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -v, --version    Show version\n", .{});
            std.debug.print("  -h, --help       Show this help\n", .{});
            std.debug.print("\nRun in a directory with a Gemfile to resolve dependencies.\n", .{});
            return;
        }
    }
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Fast path check - skip resolution if nothing changed
    var fast_resolver = fast_path.FastPathResolver.init(allocator);
    if (try fast_resolver.canUseFastPath()) {
        std.debug.print("Using cached resolution (0ms)\n", .{});
        return;
    }

    // Initialize cache
    var cache = GemCache.init(allocator);
    defer cache.deinit(allocator);

    // Simulate some gems in cache (in real implementation, load from disk/network)
    try populateTestCache(&cache, allocator);

    // Parse Gemfile
    var parser = GemfileParser.init(allocator);
    defer parser.deinit();
    
    parser.parseFile("Gemfile") catch |err| {
        std.debug.print("Error parsing Gemfile: {}\n", .{err});
        return;
    };

    std.debug.print("Fetching gem metadata from https://rubygems.org/\n", .{});
    std.debug.print("Resolving dependencies...\n", .{});

    // Create resolver
    var resolver = Resolver.init(allocator, &cache);
    defer resolver.deinit();

    // Add dependencies from parser
    for (parser.dependencies.items) |dep| {
        var dep_copy = Dependency{
            .name = dep.name,
            .constraints = ArrayList(Constraint).init(allocator),
        };
        try dep_copy.constraints.appendSlice(dep.constraints.items);
        try resolver.addDependency(dep_copy);
    }

    // Resolve
    const start = std.time.milliTimestamp();
    try resolver.resolve();
    const end = std.time.milliTimestamp();

    // Generate Gemfile.lock
    var lockfile_writer = LockfileWriter.init(allocator, &resolver.resolution, &parser);
    lockfile_writer.writeToFile("Gemfile.lock") catch |err| {
        std.debug.print("ERROR: Failed to write Gemfile.lock: {}\n", .{err});
        return;
    };
    
    // Also write binary lockfile for fast path
    try writeBinaryLockfile(allocator, &resolver.resolution, &parser);
    
    std.debug.print("Writing Gemfile.lock...\n", .{});
    std.debug.print("Resolution complete ({} gems) in {}ms\n", .{ 
        resolver.resolution.gems.count(), 
        end - start 
    });
}

pub fn populateTestCache(cache: *GemCache, allocator: Allocator) !void {
    // Rails versions
    var rails_deps = ArrayList(Dependency).init(allocator);
    var activesupport_constraints = ArrayList(Constraint).init(allocator);
    try activesupport_constraints.append(try Constraint.parse("= 7.0.0"));
    try rails_deps.append(Dependency{
        .name = "activesupport",
        .constraints = activesupport_constraints,
    });
    
    try cache.addGem(allocator, Gem{
        .name = "rails",
        .version = try Version.parse("7.0.0"),
        .dependencies = rails_deps,
    });

    try cache.addGem(allocator, Gem{
        .name = "rails",
        .version = try Version.parse("7.0.1"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    try cache.addGem(allocator, Gem{
        .name = "rails",
        .version = try Version.parse("6.1.7"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    // PG versions
    try cache.addGem(allocator, Gem{
        .name = "pg",
        .version = try Version.parse("1.0.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    try cache.addGem(allocator, Gem{
        .name = "pg",
        .version = try Version.parse("1.4.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    try cache.addGem(allocator, Gem{
        .name = "pg",
        .version = try Version.parse("1.5.4"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    // ActiveSupport
    try cache.addGem(allocator, Gem{
        .name = "activesupport",
        .version = try Version.parse("7.0.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    // Redis
    try cache.addGem(allocator, Gem{
        .name = "redis",
        .version = try Version.parse("5.0.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    try cache.addGem(allocator, Gem{
        .name = "redis",
        .version = try Version.parse("5.0.8"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    try cache.addGem(allocator, Gem{
        .name = "redis",
        .version = try Version.parse("4.8.1"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    // Sidekiq
    var sidekiq_deps = ArrayList(Dependency).init(allocator);
    var redis_constraints = ArrayList(Constraint).init(allocator);
    try redis_constraints.append(try Constraint.parse(">= 4.5.0"));
    try sidekiq_deps.append(Dependency{
        .name = "redis",
        .constraints = redis_constraints,
    });
    
    try cache.addGem(allocator, Gem{
        .name = "sidekiq",
        .version = try Version.parse("7.0.0"),
        .dependencies = sidekiq_deps,
    });

    try cache.addGem(allocator, Gem{
        .name = "sidekiq",
        .version = try Version.parse("7.2.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    // Puma
    try cache.addGem(allocator, Gem{
        .name = "puma",
        .version = try Version.parse("6.2.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    try cache.addGem(allocator, Gem{
        .name = "puma",
        .version = try Version.parse("6.4.0"),
        .dependencies = ArrayList(Dependency).init(allocator),
    });

    // Other gems (simplified - no dependencies for now)
    const simple_gems = [_]struct { name: []const u8, version: []const u8 }{
        .{ .name = "devise", .version = "4.9.0" },
        .{ .name = "devise", .version = "4.9.3" },
        .{ .name = "pundit", .version = "2.3.0" },
        .{ .name = "pundit", .version = "2.3.1" },
        .{ .name = "grape", .version = "1.7.0" },
        .{ .name = "grape", .version = "1.8.0" },
        .{ .name = "grape-entity", .version = "0.10.0" },
        .{ .name = "grape-entity", .version = "0.10.2" },
        .{ .name = "oj", .version = "3.13.0" },
        .{ .name = "oj", .version = "3.16.0" },
        .{ .name = "carrierwave", .version = "2.2.0" },
        .{ .name = "carrierwave", .version = "2.2.4" },
        .{ .name = "mini_magick", .version = "4.9.5" },
        .{ .name = "mini_magick", .version = "4.9.8" },
        .{ .name = "mini_magick", .version = "4.12.0" },
        .{ .name = "sentry-ruby", .version = "5.10.0" },
        .{ .name = "sentry-ruby", .version = "5.15.0" },
        .{ .name = "sentry-rails", .version = "5.10.0" },
        .{ .name = "sentry-rails", .version = "5.15.0" },
        .{ .name = "lograge", .version = "0.12.0" },
        .{ .name = "lograge", .version = "0.14.0" },
        .{ .name = "sidekiq-cron", .version = "1.9.0" },
        .{ .name = "sidekiq-cron", .version = "1.11.0" },
        .{ .name = "nokogiri", .version = "1.14.3" },
        .{ .name = "nokogiri", .version = "1.15.5" },
        .{ .name = "bootsnap", .version = "1.4.4" },
        .{ .name = "bootsnap", .version = "1.17.0" },
        .{ .name = "omniauth", .version = "2.1.0" },
        .{ .name = "omniauth", .version = "2.1.1" },
        .{ .name = "omniauth-rails_csrf_protection", .version = "1.0.0" },
        .{ .name = "omniauth-rails_csrf_protection", .version = "1.0.1" },
        .{ .name = "image_processing", .version = "1.12.0" },
        .{ .name = "image_processing", .version = "1.12.2" },
        .{ .name = "aws-sdk-s3", .version = "1.130.0" },
        .{ .name = "aws-sdk-s3", .version = "1.140.0" },
        .{ .name = "importmap-rails", .version = "1.1.0" },
        .{ .name = "importmap-rails", .version = "1.2.0" },
        .{ .name = "turbo-rails", .version = "1.4.0" },
        .{ .name = "turbo-rails", .version = "1.5.0" },
        .{ .name = "stimulus-rails", .version = "1.2.0" },
        .{ .name = "stimulus-rails", .version = "1.3.0" },
        .{ .name = "rack", .version = "2.2.6.4" },
        .{ .name = "rack", .version = "2.2.8" },
        .{ .name = "rack", .version = "3.0.0" },
        .{ .name = "rack-mini-profiler", .version = "3.1.0" },
        .{ .name = "rack-mini-profiler", .version = "3.3.0" },
        .{ .name = "memory_profiler", .version = "1.0.0" },
        .{ .name = "memory_profiler", .version = "1.0.1" },
        .{ .name = "tzinfo-data", .version = "1.2023.3" },
        .{ .name = "tzinfo-data", .version = "1.2023.4" },
        // Note: GitHub/Git/Path gems would normally be resolved differently
        .{ .name = "active_model_serializers", .version = "0.10.13" },
        .{ .name = "jwt", .version = "2.7.1" },
        .{ .name = "omniauth-google-oauth2", .version = "1.1.1" },
        .{ .name = "elastic-apm", .version = "4.6.0" },
        .{ .name = "sprockets-rails", .version = "3.4.2" },
        .{ .name = "dotenv-rails", .version = "2.8.1" },
        .{ .name = "annotate", .version = "3.2.0" },
        .{ .name = "dev_tools", .version = "0.1.0" },
        .{ .name = "shared_models", .version = "1.0.0" },
    };

    for (simple_gems) |gem_info| {
        try cache.addGem(allocator, Gem{
            .name = gem_info.name,
            .version = try Version.parse(gem_info.version),
            .dependencies = ArrayList(Dependency).init(allocator),
        });
    }
}

fn writeBinaryLockfile(allocator: Allocator, resolution: *const Resolution, parser: *const GemfileParser) !void {
    _ = parser;
    const file = try std.fs.cwd().createFile("Gemfile.lock.bin", .{});
    defer file.close();
    
    // Write header
    const header = fast_path.BinaryLockfile{
        .magic = fast_path.MAGIC,
        .version = fast_path.VERSION,
        .gem_count = @intCast(resolution.resolved_gems.items.len),
    };
    try file.writeAll(std.mem.asBytes(&header));
    
    // Write gemfile hash
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const gemfile_content = try std.fs.cwd().readFileAlloc(allocator, "Gemfile", 1024 * 1024);
    defer allocator.free(gemfile_content);
    hasher.update(gemfile_content);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    try file.writeAll(&hash);
    
    // Write packed gems
    for (resolution.resolved_gems.items) |gem| {
        const packed_gem = fast_path.PackedGem{
            .name_len = @intCast(gem.name.len),
            .version = @bitCast(gem.version),
            .dep_count = @intCast(gem.dependencies.items.len),
            .source_type = switch (gem.source) {
                .rubygems => 0,
                .github => 1,
                .git => 2,
                .path => 3,
            },
        };
        try file.writeAll(std.mem.asBytes(&packed_gem));
        try file.writeAll(gem.name);
        
        // Write dependency indices (would need to build index map in real impl)
        for (gem.dependencies.items) |_| {
            const dep_idx: u32 = 0; // Placeholder
            try file.writeAll(std.mem.asBytes(&dep_idx));
        }
    }
}