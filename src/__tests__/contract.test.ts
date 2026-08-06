import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_ENVIRONMENT, ENVIRONMENTS, resolveBaseUrl } from "../environments";
import { EapType, PasspointErrorCode } from "../types";

/**
 * Asserts the TypeScript SDK agrees with `core/contract/contract.json`. The
 * Swift and Kotlin suites assert the same file, so a drift in any one SDK
 * fails that SDK's build with the exact missing symbol.
 */
interface Contract {
  api: {
    apiKeyHeader: string;
    generateProfilePath: string;
    profileStatusPath: string;
    statusSubscriberQueryParam: string;
  };
  environments: Record<string, string>;
  defaultEnvironment: string;
  eapTypes: Record<string, number>;
  defaultEapType: number;
  csr: { commonNameTemplate: string };
  errorCodes: string[];
  httpStatusMapping: Record<string, string>;
}

const contract: Contract = JSON.parse(
  readFileSync(join(__dirname, "../../core/contract/contract.json"), "utf8"),
);

describe("contract conformance", () => {
  it("declares exactly the contract's error codes", () => {
    const actual = new Set(Object.values(PasspointErrorCode) as string[]);
    const expected = new Set(contract.errorCodes);

    expect([...actual].filter((c) => !expected.has(c))).toEqual([]);
    expect([...expected].filter((c) => !actual.has(c))).toEqual([]);
  });

  it("uses the enum member name as its own value", () => {
    // Native rejections arrive as the raw string; PasspointError.fromNative
    // matches them against Object.values(PasspointErrorCode).
    for (const [name, value] of Object.entries(PasspointErrorCode)) {
      expect(value).toBe(name);
    }
  });

  it("maps every environment to the contract's base URL", () => {
    for (const [name, url] of Object.entries(contract.environments)) {
      expect(resolveBaseUrl(name)).toBe(url);
    }
    expect(Object.keys(ENVIRONMENTS).sort()).toEqual(
      Object.keys(contract.environments).sort(),
    );
  });

  it("defaults to the contract's environment", () => {
    expect(DEFAULT_ENVIRONMENT).toBe(contract.defaultEnvironment);
    expect(resolveBaseUrl(DEFAULT_ENVIRONMENT)).toBe(
      contract.environments[contract.defaultEnvironment],
    );
  });

  it("declares exactly the contract's EAP types", () => {
    const numeric = Object.fromEntries(
      Object.entries(EapType).filter(([, v]) => typeof v === "number"),
    );
    expect(numeric).toEqual(contract.eapTypes);
  });

  it("defaults to the contract's EAP type", () => {
    expect(EapType.TLS).toBe(contract.defaultEapType);
  });
});

describe("resolveBaseUrl", () => {
  it("falls back to production for an unknown name", () => {
    // Matches PasspointEnvironment.named on both native platforms.
    expect(resolveBaseUrl("staging")).toBe(ENVIRONMENTS.production);
    expect(resolveBaseUrl("")).toBe(ENVIRONMENTS.production);
  });

  it("treats an http prefix as a custom deployment", () => {
    expect(resolveBaseUrl("https://api.internal.test/api/inventory/v1")).toBe(
      "https://api.internal.test/api/inventory/v1",
    );
  });

  it("strips trailing slashes from a custom deployment", () => {
    expect(resolveBaseUrl("https://api.internal.test/v1///")).toBe(
      "https://api.internal.test/v1",
    );
  });
});
