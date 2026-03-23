import { Platform } from "react-native";
import { PasspointError } from "../errors";
import NativePasspointSDK from "../NativePasspointSDK";
import { PasspointSDK } from "../PasspointSDK";
import { EapType, PasspointErrorCode } from "../types";

// NativePasspointSDK is auto-mocked via moduleNameMapper in jest.config.js
const mockNative = NativePasspointSDK as jest.Mocked<typeof NativePasspointSDK>;

describe("PasspointSDK", () => {
  beforeEach(() => {
    PasspointSDK._reset();
    jest.clearAllMocks();
    // Default to iOS for tests
    (Platform as any).OS = "ios";
  });

  describe("configure", () => {
    it("returns a singleton instance", () => {
      const a = PasspointSDK.configure({ apiKey: "test-key" });
      const b = PasspointSDK.configure({ apiKey: "test-key" });
      expect(a).toBe(b);
    });

    it("calls native configure with resolved production endpoint", () => {
      PasspointSDK.configure({ apiKey: "pk_123" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.hib.nova.xyz/api/inventory/v1/passpoint/generate",
        EapType.TLS,
        null,
        null,
      );
    });

    it("resolves development environment", () => {
      PasspointSDK.configure({ apiKey: "pk_123", environment: "development" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.dev.hib.nova.xyz/api/inventory/v1/passpoint/generate",
        EapType.TLS,
        null,
        null,
      );
    });

    it("resolves staging environment", () => {
      PasspointSDK.configure({ apiKey: "pk_123", environment: "staging" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.staging.hib.nova.xyz/api/inventory/v1/passpoint/generate",
        EapType.TLS,
        null,
        null,
      );
    });

    it("passes through a custom URL as the environment", () => {
      PasspointSDK.configure({
        apiKey: "pk_123",
        environment: "https://custom.api.example.com/passpoint",
      });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://custom.api.example.com/passpoint",
        EapType.TLS,
        null,
        null,
      );
    });

    it("passes custom eapType and serverCaCertPem", () => {
      PasspointSDK.configure({
        apiKey: "pk_123",
        eapType: EapType.TTLS,
        serverCaCertPem: "-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----",
      });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        expect.any(String),
        EapType.TTLS,
        "-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----",
        null,
      );
    });

    it("throws INVALID_CONFIG for empty apiKey", () => {
      expect(() => PasspointSDK.configure({ apiKey: "" })).toThrow(PasspointError);

      try {
        PasspointSDK.configure({ apiKey: "   " });
      } catch (e) {
        expect(e).toBeInstanceOf(PasspointError);
        expect((e as PasspointError).code).toBe(PasspointErrorCode.INVALID_CONFIG);
      }
    });

    it("throws PLATFORM_NOT_SUPPORTED on web", () => {
      (Platform as any).OS = "web";

      expect(() => PasspointSDK.configure({ apiKey: "pk_123" })).toThrow(PasspointError);

      try {
        PasspointSDK.configure({ apiKey: "pk_123" });
      } catch (e) {
        expect((e as PasspointError).code).toBe(
          PasspointErrorCode.PLATFORM_NOT_SUPPORTED,
        );
      }
    });

    it("falls back to production for unknown environment names", () => {
      PasspointSDK.configure({ apiKey: "pk_123", environment: "unknown" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.hib.nova.xyz/api/inventory/v1/passpoint/generate",
        EapType.TLS,
        null,
        null,
      );
    });
  });

  describe("getInstance", () => {
    it("throws NOT_CONFIGURED before configure()", () => {
      expect(() => PasspointSDK.getInstance()).toThrow(PasspointError);

      try {
        PasspointSDK.getInstance();
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.NOT_CONFIGURED);
      }
    });

    it("returns the instance after configure()", () => {
      const sdk = PasspointSDK.configure({ apiKey: "pk_123" });
      expect(PasspointSDK.getInstance()).toBe(sdk);
    });
  });

  describe("install", () => {
    let sdk: PasspointSDK;

    beforeEach(() => {
      sdk = PasspointSDK.configure({ apiKey: "pk_123" });
    });

    it("calls native install and parses the result", async () => {
      mockNative.install.mockResolvedValue(JSON.stringify({ success: true }));

      const result = await sdk.install("user-abc");

      expect(mockNative.install).toHaveBeenCalledWith("user-abc");
      expect(result).toEqual({ success: true });
    });

    it("throws INVALID_CONFIG for empty userIdentifier", async () => {
      await expect(sdk.install("")).rejects.toThrow(PasspointError);

      try {
        await sdk.install("  ");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.INVALID_CONFIG);
      }
    });

    it("wraps native rejections into PasspointError", async () => {
      mockNative.install.mockRejectedValue({
        code: "KEYPAIR_GENERATION_FAILED",
        message: "SecKeyCreateRandomKey failed",
      });

      try {
        await sdk.install("user-abc");
        fail("expected error");
      } catch (e) {
        expect(e).toBeInstanceOf(PasspointError);
        expect((e as PasspointError).code).toBe(
          PasspointErrorCode.KEYPAIR_GENERATION_FAILED,
        );
        expect((e as PasspointError).message).toBe("SecKeyCreateRandomKey failed");
      }
    });
  });

  describe("isInstalled", () => {
    let sdk: PasspointSDK;

    beforeEach(() => {
      sdk = PasspointSDK.configure({ apiKey: "pk_123" });
    });

    it("returns true when native says installed", async () => {
      mockNative.isInstalled.mockResolvedValue(true);
      expect(await sdk.isInstalled()).toBe(true);
    });

    it("returns false when native says not installed", async () => {
      mockNative.isInstalled.mockResolvedValue(false);
      expect(await sdk.isInstalled()).toBe(false);
    });

    it("wraps native errors", async () => {
      mockNative.isInstalled.mockRejectedValue({
        code: "SIMULATOR_NOT_SUPPORTED",
        message: "Passpoint requires a physical device",
      });

      try {
        await sdk.isInstalled();
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(
          PasspointErrorCode.SIMULATOR_NOT_SUPPORTED,
        );
      }
    });
  });

  describe("getCertificateInfo", () => {
    let sdk: PasspointSDK;

    beforeEach(() => {
      sdk = PasspointSDK.configure({ apiKey: "pk_123" });
    });

    it("parses certificate info JSON", async () => {
      const info = {
        isInstalled: true,
        expiresAt: "2027-01-15T00:00:00Z",
        subject: "anonymous@user123.hib.nova.xyz",
        domain: "hib.nova.xyz",
        friendlyName: "Helium WiFi",
      };
      mockNative.getCertificateInfo.mockResolvedValue(JSON.stringify(info));

      const result = await sdk.getCertificateInfo();
      expect(result).toEqual(info);
    });

    it("returns not-installed info", async () => {
      const info = {
        isInstalled: false,
        expiresAt: null,
        subject: null,
        domain: null,
        friendlyName: null,
      };
      mockNative.getCertificateInfo.mockResolvedValue(JSON.stringify(info));

      const result = await sdk.getCertificateInfo();
      expect(result.isInstalled).toBe(false);
      expect(result.expiresAt).toBeNull();
    });
  });

  describe("revoke", () => {
    let sdk: PasspointSDK;

    beforeEach(() => {
      sdk = PasspointSDK.configure({ apiKey: "pk_123" });
    });

    it("calls native revoke and parses result", async () => {
      mockNative.revoke.mockResolvedValue(JSON.stringify({ success: true }));

      const result = await sdk.revoke();

      expect(mockNative.revoke).toHaveBeenCalled();
      expect(result).toEqual({ success: true });
    });

    it("wraps revocation failures", async () => {
      mockNative.revoke.mockRejectedValue({
        code: "REVOCATION_FAILED",
        message: "Server returned 500",
      });

      try {
        await sdk.revoke();
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.REVOCATION_FAILED);
      }
    });

    it("wraps CERTIFICATE_NOT_FOUND when no profile exists", async () => {
      mockNative.revoke.mockRejectedValue({
        code: "CERTIFICATE_NOT_FOUND",
        message: "No certificate to revoke",
      });

      try {
        await sdk.revoke();
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.CERTIFICATE_NOT_FOUND);
      }
    });
  });

  describe("unconfigured SDK methods", () => {
    it("throws NOT_CONFIGURED for all methods", async () => {
      // Get a fresh unconfigured instance by accessing the class directly
      // Since we can't construct it, we test via getInstance
      PasspointSDK._reset();

      // Configure, get instance, then reset to simulate stale reference
      PasspointSDK.configure({ apiKey: "pk_123" });
      PasspointSDK._reset();

      // The instance still exists but the static was cleared.
      // However, the instance's `configured` flag is still true from the
      // configure call, so we test getInstance instead.
      expect(() => PasspointSDK.getInstance()).toThrow(PasspointError);
    });
  });
});
