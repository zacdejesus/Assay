// Records the Private Cloud Compute tapes. PCC needs the com.apple.developer.private-cloud-compute
// entitlement, which only a signed app can have; this app has it and nothing else.
//
// Build and run: see ../README.md ("Recording Private Cloud Compute").

import PickTwo

await Recording.recordPrivateCloudCompute()
