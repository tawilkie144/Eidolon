# Project coding standards

## Zig Guidlines
- When running tests, always run as "zig build test --sumamry all"
- Avoid using pub where possible
- tests should be located in the tests directory then mirroring the src path to the file the tests are for
- DO NOT MODIFY THE build.zig or build.zig.zon files

## Naming Convensions
- Use snake_case for variable names
- boolean variables should follow the convension is_...,has_...,can_..., etc.
- use camelCase for function
- use PascalCase for structs and enums
- use ALL_CAPS for constants

## Code Formatting
- Use 4 spaces for indentation
- Maximum line length of 100 characters
- Use `zig fmt` for automatic formatting of code
- Align related code elements vertically when it enhances readability

## Documentation
- Document public APIs with doc comments (///)
- Document tests with normal comments (//)
- When documenting tests provide the tests name and a list of what the test is verifying nothing else
- Use module doc comments (//!) at the top of each file
- Include examples in documentation for complex functions
- Document parameter and return types with meaningful descriptions

## Error Handling
- Prefer explicit error handling using `try` and error unions
- Document expected error conditions for public functions
- Use meaningful error names in error sets
- Group related errors in a single error set

## Memory Management
- Document ownership and lifetime expectations for resources
- Pass allocators as the first parameter where needed
- Clear deallocation responsibility in function documentation
- Prefer arena allocators for short-lived allocations

## Testing
- Test error conditions as well as success paths
- Use descriptive test names that explain what's being tested
- Mock dependencies for focused unit testing

## Code Organization
- Group related functions and types together
- Import ordering: std first, then external deps, then local with local seperated from the others by one line

## Functional Style
- Prefer immutable variables (const) where possible
- Minimize use of global state
- Use explicit return statements for clarity
- Consider using optionals instead of sentinel values

## Safety
- Avoid undefined behavior
- Use comptime checks for compile-time validation
- Explicitly handle all error cases
- Use @panic only for unrecoverable errors, not control flow