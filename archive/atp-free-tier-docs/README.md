# Always Free ATP Documentation (Archived)

These documents are specific to **OCI Always Free tier** ATP deployments which have limitations:

- **No private endpoints** - must use public endpoints with IP whitelisting
- **mTLS may be required** - depending on configuration

## Archived Documents

| Document | Purpose |
|----------|---------|
| [ATP_MTLS_DEPLOYMENT_GUIDE.md](ATP_MTLS_DEPLOYMENT_GUIDE.md) | mTLS wallet-based authentication setup |
| [ATP_PUBLIC_ENDPOINT_WORKAROUND.md](ATP_PUBLIC_ENDPOINT_WORKAROUND.md) | NAT Gateway IP whitelisting for Always Free |
| [ATP_QUICKSTART.md](ATP_QUICKSTART.md) | Quick setup guide for Always Free ATP |

## Production (Paid Tier)

For production deployments with paid ATP, use private endpoints:

```hcl
# modules/oci-atp configuration for production
is_free_tier    = false
use_private_endpoint = true
subnet_id       = module.network.private_subnet_id
```

This provides:
- ✅ Private endpoint (no public exposure)
- ✅ VCN-native connectivity
- ✅ Autonomous Data Guard for DR
- ✅ Higher OCPU/storage limits

See [modules/oci-atp/README.md](../../modules/oci-atp/README.md) for production configuration.
