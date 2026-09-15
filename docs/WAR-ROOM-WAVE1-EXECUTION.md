# Master Parallel War-Room — Wave 1

## Candidate
`efb30b3d23a7a9fcef22d028c33017eeab0855af`

## Execution rule
Every lane checks out the exact candidate before evidence collection. The war-room branch may contain orchestration changes, but those changes are not treated as candidate application evidence.

## Lane matrix
- fresh-db
- security
- tenant
- inventory-transfer
- finance
- orders
- imports-templates
- rbac-auth
- cms-shipping-returns
- f31
- quality

## Evidence rule
A lane is PASS only when its actual test/proof command executes and succeeds on the exact SHA. File existence, grep-only discovery, or a workflow green state without the actual assertion suite is not PASS.

## Production
NO TOUCH before F33/F34.
