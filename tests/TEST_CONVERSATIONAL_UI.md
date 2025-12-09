# Conversational UI Functional Tests

## Overview

The `test_conversational_ui.lua` test suite validates the complete Conversational UI feature for the n00bkeys plugin. These tests follow strict **anti-gaming** principles to ensure they cannot be satisfied with stub implementations.

## Test Philosophy

### Anti-Gaming Principles

1. **Test Complete Workflows**: Tests execute entire user journeys, not isolated functions
2. **Mock Only External APIs**: HTTP calls to OpenAI are mocked; everything else (file I/O, UI, state) is REAL
3. **Verify Observable Outcomes**: Tests check what users actually SEE and EXPERIENCE
4. **Validate Side Effects**: Tests verify files written, conversations persisted, state updated
5. **Ensure Durability**: Tests verify data survives close/reopen cycles

### Why These Tests Can't Be Gamed

Each test includes explicit comments explaining why it cannot be satisfied with stubs:

- **File System Checks**: Tests read actual JSON files from disk
- **Buffer Content Inspection**: Tests verify actual Neovim buffer text users see
- **API Call Validation**: Tests track full request bodies sent to OpenAI
- **State Persistence**: Tests close windows and reopen to verify durability
- **Multi-Step Workflows**: Tests execute complete user journeys with multiple interactions

## Test Categories

### Migration Tests (P0 - Critical for Data Safety)

**Why Critical**: Data loss is unacceptable. These tests ensure safe migration from v1 (flat queries) to v2 (conversations).

| Test | What It Validates | Anti-Gaming Strategy |
|------|-------------------|---------------------|
| `empty history creates v2 structure` | First-time users get v2 format | Creates real file, validates schema |
| `single v1 entry converts to v2` | One v1 query becomes one conversation | Writes real v1 file, reads v2 result, checks backup |
| `multiple v1 entries become separate conversations` | Each v1 entry becomes its own conversation | Validates all data preserved correctly |
| `corrupt v1 file fails gracefully` | Plugin doesn't crash on bad data | Creates malformed JSON, verifies no crash |

**Coverage**:
- Empty history (no file exists)
- v1 → v2 migration
- Backup creation
- Data preservation
- Error handling

### Conversation Workflow Tests (P0)

**Why Critical**: Core user experience - multi-turn conversations must work.

| Test | What It Validates | Anti-Gaming Strategy |
|------|-------------------|---------------------|
| `start conversation and send message` | Basic conversation flow works | Verifies chat UI, file persistence |
| `multi-turn conversation preserves context` | Context passed to API across turns | Inspects actual API request bodies |
| `conversation persists across close/reopen` | Conversations survive window cycles | Closes/reopens, reads from disk |
| `new conversation clears previous messages` | Ctrl-N creates separate conversation | Verifies two distinct conversations in file |

**Coverage**:
- Single-turn conversations
- Multi-turn conversations
- Context preservation in API calls
- Session persistence
- New conversation creation

### History Tab Tests (P0)

**Why Critical**: Users must see conversations (not flat queries) and be able to navigate them.

| Test | What It Validates | Anti-Gaming Strategy |
|------|-------------------|---------------------|
| `shows conversation list not flat queries` | History displays conversations | Verifies buffer shows summaries, not individual messages |
| `summary from first user message` | Summaries auto-generated from first message | Checks summary truncated correctly |
| `Enter loads full conversation` | Can resume past conversations | Opens conversation, verifies all messages present |
| `delete conversation removes all messages` | Deletion works correctly | Verifies file updated on disk |
| `clear all conversations empties history` | Clear all works | Checks file shows empty conversation list |

**Coverage**:
- Conversation list rendering
- Summary generation (first message, truncated to 50 chars)
- Navigation (Enter to open)
- Deletion (single conversation)
- Clear all

### Chat UI Tests (P1)

**Why Important**: Users need clear visual distinction between their messages and AI responses.

| Test | What It Validates | Anti-Gaming Strategy |
|------|-------------------|---------------------|
| `messages display with USER and AI labels` | Role labels present | Inspects actual buffer text |
| `multiple messages in chronological order` | Messages ordered correctly | Verifies position of messages in buffer |
| `conversation title shows summary` | Title displays summary | Checks title contains first message text |

**Coverage**:
- Role labels (USER vs AI)
- Message ordering
- Visual layout
- Conversation title

### Config Tests (P1)

**Why Important**: Users must be able to control token usage and conversation length.

| Test | What It Validates | Anti-Gaming Strategy |
|------|-------------------|---------------------|
| `max_conversation_turns limits message history` | Old messages pruned when limit exceeded | Inspects API request to verify pruning |
| `config setting can be changed` | Configuration works | Verifies config value stored |

**Coverage**:
- `max_conversation_turns` config option
- Message pruning logic
- Config validation

## Test Execution

### Running All Conversational UI Tests

```bash
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_conversational_ui.lua')"
```

### Running Specific Test Category

```bash
# Just migration tests
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run({ 'tests/test_conversational_ui.lua|Storage Migration' })"

# Just conversation workflows
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run({ 'tests/test_conversational_ui.lua|Conversation Workflow' })"
```

### Running with Make

```bash
make test  # Runs all tests including conversational UI tests
```

## Expected Initial Status

**Before Implementation**: All tests FAIL (except config tests which may partially pass)

**After Implementation**: All tests PASS

## Test Helpers

The test suite defines several child-side helpers in `_G.test_helpers`:

- `get_query_buffer_lines()` - Reads Query tab buffer content
- `get_history_buffer_lines()` - Reads History tab buffer content
- `read_history_file()` - Reads history.json from disk
- `write_v1_history(entries)` - Creates v1 format file for migration tests
- `setup_mock_with_tracking(responses)` - Mocks HTTP and tracks API calls
- `wait_for_completion()` - Waits for async operations

## Traceability to PLAN

These tests validate the following PLAN items:

### Phase 1: Storage Schema Migration (PLAN lines 33-123)
- **Tests**: All "Storage Migration" tests
- **Validates**: v2 schema, migration logic, backup creation

### Phase 2: Conversation State Management (PLAN lines 125-168)
- **Tests**: "Conversation Workflow" tests
- **Validates**: Active conversation tracking, message persistence

### Phase 3: OpenAI Integration (PLAN lines 170-218)
- **Tests**: "multi-turn conversation preserves context" test
- **Validates**: Full conversation history sent to API

### Phase 4: Chat UI Layout (PLAN lines 254-307)
- **Tests**: All "Chat UI Layout" tests
- **Validates**: Message formatting, role labels, chronological order

### Phase 5: History Tab Redesign (PLAN lines 345-557)
- **Tests**: All "History Tab Conversations" tests
- **Validates**: Conversation list, summaries, navigation, deletion

### Phase 6: Keybindings (PLAN lines 559-615)
- **Tests**: "new conversation clears previous messages" test
- **Validates**: Ctrl-N new conversation shortcut

### Phase 7: Token Management (PLAN lines 220-251)
- **Tests**: "max_conversation_turns limits message history" test
- **Validates**: Config option and message pruning

## Traceability to STATUS Report

These tests address the following STATUS report gaps:

### Critical Gaps (STATUS lines 136-188)
- **Gap**: Flat history storage (v1) vs conversation storage (v2)
- **Tests**: All "Storage Migration" tests

### API Integration Gaps (STATUS lines 226-275)
- **Gap**: Single-query API calls vs multi-turn conversation history
- **Tests**: "multi-turn conversation preserves context" test

### UI Layout Gaps (STATUS lines 276-318)
- **Gap**: Q&A layout vs chat UI
- **Tests**: All "Chat UI Layout" tests

### History Display Gaps (STATUS lines 319-364)
- **Gap**: Flat query list vs conversation list with summaries
- **Tests**: All "History Tab Conversations" tests

## What These Tests DON'T Cover

The following are intentionally NOT tested (integration/E2E layer):

1. **Ex Commands** (`:Noobkeys`, `:Nk`) - Tested in separate command integration tests
2. **Actual OpenAI API** - Mocked for cost and reliability
3. **UI Rendering Details** - Focus on content, not visual styling
4. **Performance** - No performance benchmarks in functional tests
5. **Browser/Terminal Integration** - Neovim-only, not full environment

## Test Maintenance

### When Adding New Conversation Features

1. Add test to appropriate category section
2. Include "ANTI-GAMING" comment explaining validation strategy
3. Verify test FAILS before implementing feature
4. Verify test PASSES after implementation
5. Update this documentation

### When Modifying Storage Schema

1. Add migration test for new version
2. Verify backward compatibility
3. Test with large history files (100+ entries)
4. Update schema documentation

### When Changing Chat UI

1. Update buffer content expectations in tests
2. Keep focus on user-observable content (not styling)
3. Verify tests still fail if implementation removed

## Success Criteria

**Tests are successful when**:
- ✅ All 18 tests PASS after feature implementation
- ✅ Tests FAIL when implementation is stubbed/removed
- ✅ No test can be satisfied by hardcoding expected values
- ✅ All user workflows validated end-to-end
- ✅ Data safety guaranteed (migration tests pass)

**Implementation is complete when**:
- ✅ All tests pass
- ✅ No workarounds or shortcuts in test code
- ✅ Real files created and read from disk
- ✅ Real API calls made (mocked but structurally correct)
- ✅ Real UI buffers inspected for content
