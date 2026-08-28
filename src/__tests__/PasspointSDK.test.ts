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

    it("calls native configure with the resolved production base URL", () => {
      PasspointSDK.configure({ apiKey: "pk_123" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.prod.hib.nova.xyz/api/inventory/v1",
        EapType.TLS,
        null,
        null,
        null,
      );
    });

    it("resolves development environment", () => {
      PasspointSDK.configure({ apiKey: "pk_123", environment: "development" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api-dev.dev.hib.nova.xyz/api/inventory/v1",
        EapType.TLS,
        null,
        null,
        null,
      );
    });

    it("resolves poc environment", () => {
      PasspointSDK.configure({ apiKey: "pk_123", environment: "poc" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.dev.hib.nova.xyz/api/inventory/v1",
        EapType.TLS,
        null,
        null,
        null,
      );
    });

    it("falls back to production for unmapped environments like staging", () => {
      PasspointSDK.configure({ apiKey: "pk_123", environment: "staging" });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://api.prod.hib.nova.xyz/api/inventory/v1",
        EapType.TLS,
        null,
        null,
        null,
      );
    });

    it("passes through a custom URL as the base URL, stripping trailing slashes", () => {
      PasspointSDK.configure({
        apiKey: "pk_123",
        environment: "https://custom.api.example.com/api/inventory/v1/",
      });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        "https://custom.api.example.com/api/inventory/v1",
        EapType.TLS,
        null,
        null,
        null,
      );
    });

    it("passes custom eapType, serverCaCertPem, and presetId", () => {
      PasspointSDK.configure({
        apiKey: "pk_123",
        eapType: EapType.TTLS,
        serverCaCertPem: "-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----",
        presetId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      });

      expect(mockNative.configure).toHaveBeenCalledWith(
        "pk_123",
        expect.any(String),
        EapType.TTLS,
        "-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----",
        null,
        "7c9e6679-7425-40de-944b-e07fc1f90ae7",
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
        "https://api.prod.hib.nova.xyz/api/inventory/v1",
        EapType.TLS,
        null,
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

      const result = await sdk.install("sub-abc");

      expect(mockNative.install).toHaveBeenCalledWith("sub-abc");
      expect(result).toEqual({ success: true });
    });

    it("throws INVALID_CONFIG for empty subscriberId", async () => {
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
        await sdk.install("sub-abc");
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
        subject: "anonymous@sub123.hib.nova.xyz",
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

  describe("getRemoteStatus", () => {
    let sdk: PasspointSDK;

    beforeEach(() => {
      sdk = PasspointSDK.configure({ apiKey: "pk_123" });
    });

    it("parses a RemoteProfileStatus response", async () => {
      const status = {
        subscriberId: "sub-001",
        presetId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        eapType: 13,
        expiresAt: "2027-01-15T10:30:00Z",
        active: true,
      };
      mockNative.getRemoteStatus.mockResolvedValue(JSON.stringify(status));

      const result = await sdk.getRemoteStatus("sub-001");

      expect(mockNative.getRemoteStatus).toHaveBeenCalledWith("sub-001");
      expect(result).toEqual(status);
    });

    it("returns null when the native bridge reports no profile", async () => {
      mockNative.getRemoteStatus.mockResolvedValue("null");

      const result = await sdk.getRemoteStatus("sub-404");

      expect(result).toBeNull();
    });

    it("throws INVALID_CONFIG for empty subscriberId", async () => {
      await expect(sdk.getRemoteStatus("")).rejects.toThrow(PasspointError);

      try {
        await sdk.getRemoteStatus("  ");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.INVALID_CONFIG);
      }
    });

    it("wraps API_UNAUTHORIZED native rejections", async () => {
      mockNative.getRemoteStatus.mockRejectedValue({
        code: "API_UNAUTHORIZED",
        message: "API key rejected",
      });

      try {
        await sdk.getRemoteStatus("sub-001");
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.API_UNAUTHORIZED);
      }
    });

    it("wraps NETWORK_ERROR native rejections", async () => {
      mockNative.getRemoteStatus.mockRejectedValue({
        code: "NETWORK_ERROR",
        message: "timeout",
      });

      try {
        await sdk.getRemoteStatus("sub-001");
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.NETWORK_ERROR);
      }
    });
  });

  describe("remove", () => {
    let sdk: PasspointSDK;

    beforeEach(() => {
      sdk = PasspointSDK.configure({ apiKey: "pk_123" });
    });

    it("calls native remove and parses result", async () => {
      mockNative.remove.mockResolvedValue(JSON.stringify({ success: true }));

      const result = await sdk.remove();

      expect(mockNative.remove).toHaveBeenCalled();
      expect(result).toEqual({ success: true });
    });

    it("wraps removal failures", async () => {
      mockNative.remove.mockRejectedValue({
        code: "REMOVE_FAILED",
        message: "Failed to remove profile",
      });

      try {
        await sdk.remove();
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.REMOVE_FAILED);
      }
    });

    it("wraps CERTIFICATE_NOT_FOUND when no profile exists", async () => {
      mockNative.remove.mockRejectedValue({
        code: "CERTIFICATE_NOT_FOUND",
        message: "No certificate to remove",
      });

      try {
        await sdk.remove();
        fail("expected error");
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.CERTIFICATE_NOT_FOUND);
      }
    });
  });

  describe("eapType validation", () => {
    it("accepts every declared EAP type", () => {
      for (const value of [EapType.TLS, EapType.TTLS, EapType.PEAP]) {
        PasspointSDK._reset();
        expect(() =>
          PasspointSDK.configure({ apiKey: "test-key", eapType: value }),
        ).not.toThrow();
        expect(mockNative.configure).toHaveBeenLastCalledWith(
          "test-key",
          expect.any(String),
          value,
          null,
          null,
          null,
        );
      }
    });

    it("rejects a value outside the enum instead of silently using EAP-TLS", () => {
      PasspointSDK._reset();
      expect(() =>
        PasspointSDK.configure({ apiKey: "test-key", eapType: 18 as EapType }),
      ).toThrow(PasspointError);
      expect(mockNative.configure).not.toHaveBeenCalled();
    });
  });

  describe("unconfigured SDK methods", () => {
    // Previously this block only re-asserted getInstance(), so ensureConfigured()
    // could be deleted entirely and every test still passed. Reach the instance
    // methods directly to actually exercise the guard.
    function unconfiguredInstance(): PasspointSDK {
      const sdk = PasspointSDK.configure({ apiKey: "test-key" });
      PasspointSDK._reset();
      // The instance object survives the reset; its `configured` flag is what
      // ensureConfigured() checks, so clear it the way a fresh instance would be.
      (sdk as unknown as { configured: boolean }).configured = false;
      return sdk;
    }

    it.each([
      ["install", (sdk: PasspointSDK) => sdk.install("sub-1")],
      ["isInstalled", (sdk: PasspointSDK) => sdk.isInstalled()],
      ["getCertificateInfo", (sdk: PasspointSDK) => sdk.getCertificateInfo()],
      ["getRemoteStatus", (sdk: PasspointSDK) => sdk.getRemoteStatus("sub-1")],
      ["remove", (sdk: PasspointSDK) => sdk.remove()],
    ])("%s rejects with NOT_CONFIGURED", async (_name, call) => {
      const sdk = unconfiguredInstance();
      mockNative.isInstalled.mockResolvedValue(true);

      await expect(call(sdk)).rejects.toMatchObject({
        code: PasspointErrorCode.NOT_CONFIGURED,
      });
      expect(mockNative.isInstalled).not.toHaveBeenCalled();
    });

    it("getInstance throws NOT_CONFIGURED before configure", () => {
      PasspointSDK._reset();
      expect(() => PasspointSDK.getInstance()).toThrow(PasspointError);
      try {
        PasspointSDK.getInstance();
      } catch (e) {
        expect((e as PasspointError).code).toBe(PasspointErrorCode.NOT_CONFIGURED);
      }
    });
  });
});
