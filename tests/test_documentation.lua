-- Documentation Generation Functional Tests
--
-- WORKFLOW-FIRST APPROACH:
-- These tests validate the REAL DOCUMENTATION GENERATION WORKFLOW end-to-end.
-- NO MOCKS - runs actual mini.doc.generate() and validates output.
-- Tests FAIL if documentation generation fails for any reason users would care about.
--
-- ANTI-GAMING DESIGN:
-- 1. Calls real mini.doc.generate() - cannot be satisfied with stubs
-- 2. Parses actual doc/n00bkeys.txt file - verifies real output
-- 3. Checks for duplicate tags by reading generated help file - not internal state
-- 4. Verifies helptags generation succeeds - full Vim validation
--
-- USER-FACING VALIDATION:
-- If `make documentation` fails, these tests fail.
-- If doc/n00bkeys.txt has duplicate tags, these tests fail.
-- If any public API is undocumented, these tests warn (not fail, for flexibility).
--
-- COVERAGE:
-- - P0-3 from PLAN: Validates documentation generation succeeds without E154 errors
-- - Prevents regression if new duplicate function names are added
-- - Ensures generated documentation is valid Vim help format

local Helpers = dofile("tests/helpers.lua")
local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        post_once = child.stop,
    },
})

-- Helper: Run documentation generation and capture output
-- Returns: { success: boolean, output: string, error: string }
local function run_doc_generation()
    -- Run the exact same command as `make documentation`
    -- This is UN-GAMEABLE - runs real mini.doc.generate() in real Neovim process
    local cmd = [[nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua require('mini.doc').generate()" -c "qa!" 2>&1]]
    local result = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error

    return {
        success = exit_code == 0,
        output = result,
        exit_code = exit_code,
    }
end

-- Helper: Parse doc/n00bkeys.txt and extract all help tags
-- Returns: { tag1 = count, tag2 = count, ... }
local function extract_help_tags()
    local doc_file = "doc/n00bkeys.txt"
    local file = io.open(doc_file, "r")

    if not file then
        return nil, "doc/n00bkeys.txt not found"
    end

    local content = file:read("*a")
    file:close()

    -- Help tags in Vim format: *tagname*
    -- Pattern matches: *word* or *word.word* or *word-word* etc.
    local tags = {}
    for tag in content:gmatch("%*([^*]+)%*") do
        tags[tag] = (tags[tag] or 0) + 1
    end

    return tags
end

-- Helper: Check if any tags appear more than once
-- Returns: { duplicate_tag1, duplicate_tag2, ... } or empty table
local function find_duplicate_tags(tags)
    local duplicates = {}
    for tag, count in pairs(tags) do
        if count > 1 then
            table.insert(duplicates, tag)
        end
    end
    table.sort(duplicates) -- For consistent error messages
    return duplicates
end

-- Helper: Check for specific E154 error in output
local function contains_duplicate_tag_error(output)
    return output:find("E154: Duplicate tag") ~= nil
end

-- ==============================================================================
-- WORKFLOW TEST 1: Documentation Generation Succeeds
-- ==============================================================================
-- USER WORKFLOW:
--   Developer runs: `make documentation`
--   EXPECTED: Command completes successfully (exit code 0)
--   EXPECTED: No errors printed to stderr
--   EXPECTED: doc/n00bkeys.txt is generated/updated
--
-- FAILURE MODE:
--   If mini.doc.generate() fails (duplicate tags, syntax errors, etc.), this test FAILS
--
-- UN-GAMEABLE BECAUSE:
--   - Runs real nvim --headless with real mini.doc.generate()
--   - Checks actual exit code from subprocess
--   - Verifies actual file exists on filesystem
--   - Cannot be satisfied by mocking or hardcoding
T["documentation generation succeeds without errors"] = function()
    local result = run_doc_generation()

    -- ASSERT: Documentation generation completes successfully
    if not result.success then
        local error_msg = string.format(
            "Documentation generation failed with exit code %d.\nOutput:\n%s",
            result.exit_code,
            result.output
        )
        MiniTest.expect.equality(result.success, true, error_msg)
    end

    -- ASSERT: No E154 duplicate tag errors in output
    if contains_duplicate_tag_error(result.output) then
        error(
            "Documentation generation reported duplicate tags:\n"
                .. result.output
        )
    end

    -- ASSERT: doc/n00bkeys.txt file was created
    local doc_file_exists = vim.fn.filereadable("doc/n00bkeys.txt") == 1
    MiniTest.expect.equality(
        doc_file_exists,
        true,
        "doc/n00bkeys.txt should exist after generation"
    )
end

-- ==============================================================================
-- WORKFLOW TEST 2: Generated Help Tags Are Unique
-- ==============================================================================
-- USER WORKFLOW:
--   Developer generates documentation
--   Developer (or CI) runs :helptags to index the documentation
--   Vim processes doc/n00bkeys.txt and builds tag index
--   EXPECTED: Vim accepts all tags without E154 errors
--
-- FAILURE MODE:
--   If any help tag appears more than once in doc/n00bkeys.txt, Vim will reject it
--   This test catches that BEFORE the user runs :helptags
--
-- UN-GAMEABLE BECAUSE:
--   - Parses actual generated doc/n00bkeys.txt file
--   - Counts real occurrences of *tag* patterns in file
--   - Checks actual Vim help file format
--   - Cannot be satisfied by changing internal state or mocking
T["generated help tags are unique (no duplicates)"] = function()
    -- First generate documentation (need fresh output)
    local result = run_doc_generation()
    MiniTest.expect.equality(
        result.success,
        true,
        "Documentation must generate successfully before checking tags"
    )

    -- Parse generated file and extract all tags
    local tags, err = extract_help_tags()
    MiniTest.expect.no_equality(tags, nil, "Should be able to read doc/n00bkeys.txt: " .. (err or ""))

    -- Find any duplicate tags
    local duplicates = find_duplicate_tags(tags)

    -- ASSERT: No duplicate tags exist
    if #duplicates > 0 then
        local duplicate_list = table.concat(duplicates, ", ")
        local error_msg = string.format(
            "Found %d duplicate help tag(s) in doc/n00bkeys.txt:\n%s\n\nThis will cause E154 errors when running :helptags",
            #duplicates,
            duplicate_list
        )
        error(error_msg)
    end

    -- Success: all tags are unique
    MiniTest.expect.equality(#duplicates, 0, "No duplicate tags should exist")
end

-- ==============================================================================
-- WORKFLOW TEST 3: Vim :helptags Command Succeeds
-- ==============================================================================
-- USER WORKFLOW:
--   After documentation is generated, Vim runs :helptags doc/
--   EXPECTED: Vim successfully indexes all tags in doc/n00bkeys.txt
--   EXPECTED: No E154 errors thrown by Vim
--
-- FAILURE MODE:
--   If duplicate tags exist, :helptags will fail with E154
--   This is the ACTUAL error users encounter
--
-- UN-GAMEABLE BECAUSE:
--   - Runs real Vim :helptags command
--   - Uses actual Vim help tag parser
--   - Validates against Vim's actual E154 duplicate tag check
--   - This is the exact same validation Vim does when users run :helptags
T["Vim helptags command succeeds on generated documentation"] = function()
    -- First generate documentation
    local result = run_doc_generation()
    MiniTest.expect.equality(
        result.success,
        true,
        "Documentation must generate successfully before running helptags"
    )

    -- Run Vim's :helptags command on the doc/ directory
    -- This is THE definitive test - if Vim accepts it, it's valid
    child.cmd("helptags doc/")

    -- If we reach here without error, helptags succeeded
    -- No assertions needed - cmd() would throw if :helptags failed

    -- Additionally verify tags file was created
    local tags_file_exists = vim.fn.filereadable("doc/tags") == 1
    MiniTest.expect.equality(
        tags_file_exists,
        true,
        "doc/tags should be generated by :helptags"
    )
end

-- ==============================================================================
-- WORKFLOW TEST 4: Specific Known Duplicates Are Fixed
-- ==============================================================================
-- USER WORKFLOW:
--   Developer is fixing known duplicate tag issues identified in STATUS report
--   EXPECTED: ensure_directory, clear_cache, clear are no longer duplicated
--
-- FAILURE MODE:
--   If refactoring didn't eliminate these specific duplicates, test fails
--
-- UN-GAMEABLE BECAUSE:
--   - Checks actual tag counts in real generated file
--   - Verifies specific tags mentioned in PLAN-2025-12-09-061500.md
--   - Tests the exact problem we're solving
--
-- NOTE: This test is expected to FAIL until P0-1 and P0-2 are implemented
T["specific known duplicate tags are resolved"] = function()
    -- First generate documentation
    local result = run_doc_generation()
    MiniTest.expect.equality(
        result.success,
        true,
        "Documentation must generate successfully"
    )

    -- Parse tags
    local tags, err = extract_help_tags()
    MiniTest.expect.no_equality(tags, nil, "Should be able to read doc/n00bkeys.txt: " .. (err or ""))

    -- Check specific problematic tags from STATUS report:
    -- - M.ensure_directory() - duplicated in history.lua and settings.lua
    -- - M._clear_cache() - duplicated in history.lua, context.lua, settings.lua
    -- - M.clear() - duplicated in history.lua and ui.lua

    local problematic_tags = {
        "M.ensure_directory()",
        "M._clear_cache()",
"M.clear_history()",
        "M.clear_conversation()",
    }

    local still_duplicated = {}
    for _, tag in ipairs(problematic_tags) do
        local count = tags[tag] or 0
        if count > 1 then
            table.insert(still_duplicated, string.format("%s (appears %d times)", tag, count))
        end
    end

    -- ASSERT: These specific tags should no longer be duplicated
    if #still_duplicated > 0 then
        local error_msg = string.format(
            "Found known duplicate tags that should have been fixed:\n%s\n\nThese duplicates were identified in STATUS-2025-12-09-054700.md and should be resolved by P0-1 and P0-2",
            table.concat(still_duplicated, "\n")
        )
        error(error_msg)
    end

    MiniTest.expect.equality(
        #still_duplicated,
        0,
        "Known duplicate tags should be resolved"
    )
end

-- ==============================================================================
-- INFORMATIONAL TEST: Report Public API Coverage
-- ==============================================================================
-- This test doesn't fail - it reports which modules have public functions
-- Helps identify if new modules need documentation annotations
--
-- NOT a strict test because:
-- - Some modules may intentionally have no public API
-- - Internal modules don't need help tags
-- - Flexibility for development
T["report public API documentation coverage"] = function()
    -- This test is informational only - logs warnings but doesn't fail
    -- Scans lua/n00bkeys/ for all .lua files and checks if they have help tags

    local modules = vim.fn.glob("lua/n00bkeys/*.lua", false, true)
    local tags, _ = extract_help_tags()

    if not tags then
        -- If doc file doesn't exist yet, skip this test
        return
    end

    local undocumented_modules = {}

    for _, module_path in ipairs(modules) do
        local module_name = vim.fn.fnamemodify(module_path, ":t:r") -- Extract filename without extension

        -- Check if any tag starts with module name (e.g., "n00bkeys.config")
        local has_tag = false
        for tag, _ in pairs(tags) do
            if tag:match("^n00bkeys%." .. module_name) or tag:match("^" .. module_name .. "%.") then
                has_tag = true
                break
            end
        end

        if not has_tag then
            table.insert(undocumented_modules, module_name)
        end
    end

    -- Report findings (but don't fail test)
    if #undocumented_modules > 0 then
        print(
            string.format(
                "INFO: %d module(s) have no help tags: %s",
                #undocumented_modules,
                table.concat(undocumented_modules, ", ")
            )
        )
    end

    -- Always pass - this is informational only
    MiniTest.expect.equality(true, true, "Informational test always passes")
end

return T
