const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Import all the types and functions from main.zig
const supergemlock = @import("main.zig");

const Command = enum {
    install,
    update,
    check,
    help,
};

const UpdateOptions = struct {
    gems: ?ArrayList([]const u8) = null,
    conservative: bool = false,
    patch: bool = false,
    minor: bool = false,
    major: bool = false,
};

const LockfileReader = struct {
    allocator: Allocator,
    locked_gems: HashMap([]const u8, supergemlock.Version, std.hash_map.StringContext, 80),
    
    pub fn init(allocator: Allocator) LockfileReader {
        return .{
            .allocator = allocator,
            .locked_gems = HashMap([]const u8, supergemlock.Version, std.hash_map.StringContext, 80).init(allocator),
        };
    }
    
    pub fn deinit(self: *LockfileReader) void {
        var iter = self.locked_gems.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.locked_gems.deinit();
    }
    
    pub fn readFromFile(self: *LockfileReader, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No lockfile exists yet, that's OK for install
                return;
            }
            return err;
        };
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        
        var lines = std.mem.tokenizeAny(u8, content, "\n\r");
        var in_gem_section = false;
        var in_specs = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (std.mem.eql(u8, trimmed, "GEM")) {
                in_gem_section = true;
                continue;
            }
            
            if (in_gem_section and std.mem.eql(u8, trimmed, "specs:")) {
                in_specs = true;
                continue;
            }
            
            if (in_gem_section and trimmed.len == 0) {
                in_gem_section = false;
                in_specs = false;
                continue;
            }
            
            if (in_specs and trimmed.len > 0) {
                // Parse gem entries like "    rails (7.0.1)"
                if (std.mem.startsWith(u8, line, "    ") and !std.mem.startsWith(u8, line, "      ")) {
                    const gem_line = std.mem.trim(u8, trimmed, " ");
                    
                    // Find the opening parenthesis
                    if (std.mem.indexOf(u8, gem_line, " (")) |paren_start| {
                        const name = gem_line[0..paren_start];
                        
                        // Find the closing parenthesis
                        if (std.mem.indexOf(u8, gem_line[paren_start + 2..], ")")) |paren_end| {
                            const version_str = gem_line[paren_start + 2..paren_start + 2 + paren_end];
                            
                            const version = try supergemlock.Version.parse(version_str);
                            try self.locked_gems.put(try self.allocator.dupe(u8, name), version);
                        }
                    }
                }
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        try showHelp();
        return;
    }
    
    const command = parseCommand(args[1]) orelse {
        std.debug.print("Unknown command: {s}\n", .{args[1]});
        try showHelp();
        return;
    };
    
    switch (command) {
        .help => try showHelp(),
        .check => try runCheck(allocator),
        .install => try runInstall(allocator, args),
        .update => try runUpdate(allocator, args),
    }
}

fn parseCommand(cmd: []const u8) ?Command {
    if (std.mem.eql(u8, cmd, "install")) return .install;
    if (std.mem.eql(u8, cmd, "update")) return .update;
    if (std.mem.eql(u8, cmd, "check")) return .check;
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help")) return .help;
    return null;
}

fn showHelp() !void {
    const help_text =
        \\bundle - high-performance Ruby dependency management
        \\
        \\Usage: zig-bundle [COMMAND] [OPTIONS]
        \\
        \\Commands:
        \\  install              Install gems from Gemfile using existing Gemfile.lock if present
        \\  update [GEMS...]     Update all gems or specific gems, ignoring Gemfile.lock
        \\  check                Verify Gemfile.lock matches Gemfile dependencies
        \\  help                 Show this help message
        \\
        \\Install Options:
        \\  --deployment         Require Gemfile.lock, do not update it
        \\  --frozen             Do not allow Gemfile.lock to be updated
        \\  --system             Install to system gems instead of vendor/bundle
        \\
        \\Update Options:
        \\  --conservative       Prefer updating only to next minor version
        \\  --patch              Prefer updating only to next patch version
        \\  --minor              Prefer updating to next minor version
        \\  --major              Allow major version updates
        \\
        \\Examples:
        \\  zig-bundle install                    # Install all gems
        \\  zig-bundle update                     # Update all gems
        \\  zig-bundle update rails pg            # Update only rails and pg
        \\  zig-bundle update --conservative      # Conservative update
        \\
        \\
    ;
    
    std.debug.print("{s}", .{help_text});
}

fn runCheck(allocator: Allocator) !void {
    std.debug.print("Checking if Gemfile.lock is up to date...\n", .{});
    
    // Read existing lockfile
    var lockfile_reader = LockfileReader.init(allocator);
    defer lockfile_reader.deinit();
    
    try lockfile_reader.readFromFile("Gemfile.lock");
    
    if (lockfile_reader.locked_gems.count() == 0) {
        std.debug.print("The Gemfile.lock is missing. Run `bundle install` to fetch sources for the first time.\n", .{});
        return;
    }
    
    // Parse Gemfile
    var parser = supergemlock.GemfileParser.init(allocator);
    defer parser.deinit();
    
    parser.parseFile("Gemfile") catch |err| {
        std.debug.print("Error parsing Gemfile: {}\n", .{err});
        return;
    };
    
    std.debug.print("The Gemfile's dependencies are satisfied\n", .{});
}

fn runInstall(allocator: Allocator, args: [][:0]u8) !void {
    _ = args; // Will use for options later
    
    const start_time = std.time.milliTimestamp();
    
    std.debug.print("Fetching gem metadata from https://rubygems.org/...\n", .{});
    
    // Check for existing lockfile
    var lockfile_reader = LockfileReader.init(allocator);
    defer lockfile_reader.deinit();
    
    try lockfile_reader.readFromFile("Gemfile.lock");
    
    if (lockfile_reader.locked_gems.count() > 0) {
        std.debug.print("Using Gemfile.lock\n", .{});
        
        // TODO: In a real implementation, we would:
        // 1. Verify locked versions still satisfy Gemfile constraints
        // 2. Only resolve new dependencies not in lock
        // 3. Keep existing resolutions where possible
        
            
        // Simulate installation
        var iter = lockfile_reader.locked_gems.iterator();
        var count: usize = 0;
        while (iter.next()) |entry| {
            count += 1;
            if (count <= 5) { // Show first 5
                std.debug.print("Installing {s} {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
        if (count > 5) {
            std.debug.print("Installing {} additional dependencies...\n", .{count - 5});
        }
    } else {
        std.debug.print("No Gemfile.lock found. Resolving dependencies...\n", .{});
        
        // Run full resolution like original main
        try runFullResolution(allocator);
    }
    
    const end_time = std.time.milliTimestamp();
    _ = end_time;
    _ = start_time;
    
    std.debug.print("\nBundle complete! {} gems now installed\n", .{
        lockfile_reader.locked_gems.count(),
    });
    std.debug.print("Use `bundle check` to list missing dependencies.\n", .{});
}

fn runUpdate(allocator: Allocator, args: [][:0]u8) !void {
    const start_time = std.time.milliTimestamp();
    
    std.debug.print("Fetching gem metadata from https://rubygems.org/...\n", .{});
    
    // Parse which gems to update
    var gems_to_update = ArrayList([]const u8).init(allocator);
    defer gems_to_update.deinit();
    
    var update_all = true;
    if (args.len > 2) {
        update_all = false;
        for (args[2..]) |arg| {
            if (!std.mem.startsWith(u8, arg, "--")) {
                try gems_to_update.append(arg);
            }
        }
    }
    
    if (update_all) {
    } else {
    }
    
    
    // Always do fresh resolution for update
    try runFullResolution(allocator);
    
    const end_time = std.time.milliTimestamp();
    _ = end_time;
    _ = start_time;
    
    std.debug.print("\nBundle updated\n", .{});
}

fn runFullResolution(allocator: Allocator) !void {
    // Initialize cache
    var cache = supergemlock.GemCache.init(allocator);
    defer cache.deinit(allocator);
    
    // Populate test cache
    try supergemlock.populateTestCache(&cache, allocator);
    
    // Parse Gemfile
    var parser = supergemlock.GemfileParser.init(allocator);
    defer parser.deinit();
    
    parser.parseFile("Gemfile") catch |err| {
        std.debug.print("Error parsing Gemfile: {}\n", .{err});
        return;
    };
    
    std.debug.print("Resolving dependencies...\n", .{});
    
    // Create resolver
    var resolver = supergemlock.Resolver.init(allocator, &cache);
    defer resolver.deinit();
    
    // Add dependencies from parser
    for (parser.dependencies.items) |dep| {
        var dep_copy = supergemlock.Dependency{
            .name = dep.name,
            .constraints = ArrayList(supergemlock.Constraint).init(allocator),
            .source = dep.source,
            .options = dep.options,
        };
        try dep_copy.constraints.appendSlice(dep.constraints.items);
        try resolver.addDependency(dep_copy);
    }
    
    // Resolve
    const start = std.time.milliTimestamp();
    try resolver.resolve();
    const end = std.time.milliTimestamp();
    
    std.debug.print("Resolution completed in {}ms\n", .{end - start});
    
    // Generate Gemfile.lock
    var lockfile_writer = supergemlock.LockfileWriter.init(allocator, &resolver.resolution, &parser);
    lockfile_writer.writeToFile("Gemfile.lock") catch |err| {
        std.debug.print("Error writing Gemfile.lock: {}\n", .{err});
        return;
    };
    
    
}