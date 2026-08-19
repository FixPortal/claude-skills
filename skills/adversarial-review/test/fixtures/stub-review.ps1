param(
    [string] $Instruction,
    [string] $DiffPath,
    [string] $FindingsPath,
    [string] $ContextPath,
    [string] $Model
)

if ($FindingsPath) {
    'F1: AGREE - telemetry fixture'
} else {
    @'
### Telemetry fixture
- **Severity:** Low
- **Location:** sample.txt:1
- **Trigger:** fixture
- **Issue:** fixture
- **Impact:** fixture
- **Suggested fix:** fixture
'@
}
