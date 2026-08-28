/**
 * Inventory API deployments.
 *
 * These must stay identical to `PasspointEnvironment` in the Swift and Kotlin
 * SDKs; `src/__tests__/contract.test.ts` asserts all three against
 * `core/contract/contract.json`.
 */
export const ENVIRONMENTS: Record<string, string> = {
  production: "https://api.prod.hib.nova.xyz/api/inventory/v1",
  development: "https://api-dev.dev.hib.nova.xyz/api/inventory/v1",
  poc: "https://api.dev.hib.nova.xyz/api/inventory/v1",
};

/** Used when `environment` is omitted, or names a deployment we don't know. */
export const DEFAULT_ENVIRONMENT = "production";

/**
 * Resolve an `environment` config value to a base URL.
 *
 * A value starting with `http` is treated as a custom deployment and used
 * verbatim (minus trailing slashes). Anything else is looked up by name, and an
 * unknown name falls back to production rather than throwing — matching
 * `PasspointEnvironment.named` on both native platforms.
 */
export function resolveBaseUrl(environment: string): string {
  if (environment.startsWith("http")) return environment.replace(/\/+$/, "");
  return ENVIRONMENTS[environment] ?? ENVIRONMENTS[DEFAULT_ENVIRONMENT];
}
