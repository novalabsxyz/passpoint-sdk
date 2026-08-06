import { act, renderHook, waitFor } from "@testing-library/react-native";
import type React from "react";
import { Platform } from "react-native";
// Imported by path, not from "react-native": jest's moduleNameMapper points at
// this exact file, so it is the same module instance the SDK sees, but
// TypeScript resolves the real react-native types for the bare specifier.
import { __appStateListenerCount, __emitAppState } from "../__mocks__/react-native";
import { PasspointError } from "../errors";
import NativePasspointSDK from "../NativePasspointSDK";
import { PasspointProvider } from "../PasspointProvider";
import { PasspointSDK } from "../PasspointSDK";
import { PasspointErrorCode } from "../types";
import { usePasspoint } from "../usePasspoint";

const mockNative = NativePasspointSDK as jest.Mocked<typeof NativePasspointSDK>;

const CERT_INFO_INSTALLED = JSON.stringify({
  isInstalled: true,
  expiresAt: "2027-01-15T00:00:00Z",
  subject: "anonymous@user123.hib.nova.xyz",
  domain: "hib.nova.xyz",
  friendlyName: "Helium WiFi",
});

const CERT_INFO_NOT_INSTALLED = JSON.stringify({
  isInstalled: false,
  expiresAt: null,
  subject: null,
  domain: null,
  friendlyName: null,
});

function wrapper({ children }: { children: React.ReactNode }) {
  return (
    <PasspointProvider config={{ apiKey: "test-key" }}>{children}</PasspointProvider>
  );
}

describe("usePasspoint", () => {
  beforeEach(() => {
    PasspointSDK._reset();
    jest.clearAllMocks();
    (Platform as any).OS = "ios";

    // Default: no profile installed
    mockNative.isInstalled.mockResolvedValue(false);
    mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_NOT_INSTALLED);
  });

  it("throws when used outside PasspointProvider", () => {
    // Suppress console.error from React for the expected error
    const spy = jest.spyOn(console, "error").mockImplementation(() => {});

    expect(() => {
      renderHook(() => usePasspoint());
    }).toThrow(PasspointError);

    spy.mockRestore();
  });

  it("checks installation status on mount", async () => {
    mockNative.isInstalled.mockResolvedValue(false);

    const { result } = renderHook(() => usePasspoint(), { wrapper });

    // Initially null (loading)
    expect(result.current.isInstalled).toBeNull();

    await waitFor(() => {
      expect(result.current.isInstalled).toBe(false);
    });

    expect(mockNative.isInstalled).toHaveBeenCalled();
  });

  it("reports installed status when profile exists", async () => {
    mockNative.isInstalled.mockResolvedValue(true);
    mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);

    const { result } = renderHook(() => usePasspoint(), { wrapper });

    await waitFor(() => {
      expect(result.current.isInstalled).toBe(true);
    });

    expect(result.current.certificateInfo?.expiresAt).toBe("2027-01-15T00:00:00Z");
  });

  describe("install", () => {
    it("installs and updates state", async () => {
      mockNative.install.mockResolvedValue(JSON.stringify({ success: true }));

      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      // After install, native will report installed
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);

      let installResult: any;
      await act(async () => {
        installResult = await result.current.install("sub-abc");
      });

      expect(installResult).toEqual({ success: true });
      expect(result.current.isInstalled).toBe(true);
      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it("sets error state on failure", async () => {
      mockNative.install.mockRejectedValue({
        code: "KEYPAIR_GENERATION_FAILED",
        message: "Key generation failed",
      });

      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      await act(async () => {
        try {
          await result.current.install("sub-abc");
        } catch {
          // expected
        }
      });

      expect(result.current.error).toBeInstanceOf(PasspointError);
      expect(result.current.error?.code).toBe(
        PasspointErrorCode.KEYPAIR_GENERATION_FAILED,
      );
      expect(result.current.isLoading).toBe(false);
    });

    it("clears previous error on new attempt", async () => {
      // First call fails
      mockNative.install.mockRejectedValueOnce({
        code: "NETWORK_ERROR",
        message: "timeout",
      });

      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      await act(async () => {
        try {
          await result.current.install("sub-abc");
        } catch {
          // expected
        }
      });

      expect(result.current.error?.code).toBe(PasspointErrorCode.NETWORK_ERROR);

      // Second call succeeds
      mockNative.install.mockResolvedValue(JSON.stringify({ success: true }));
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);

      await act(async () => {
        await result.current.install("sub-abc");
      });

      expect(result.current.error).toBeNull();
    });
  });

  describe("remove", () => {
    it("removes and updates state", async () => {
      // Start with installed profile
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);
      mockNative.remove.mockResolvedValue(JSON.stringify({ success: true }));

      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(true);
      });

      let removeResult: any;
      await act(async () => {
        removeResult = await result.current.remove();
      });

      expect(removeResult).toEqual({ success: true });
      expect(result.current.isInstalled).toBe(false);
      expect(result.current.certificateInfo).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it("sets error state on removal failure", async () => {
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);
      mockNative.remove.mockRejectedValue({
        code: "REMOVE_FAILED",
        message: "Removal error",
      });

      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(true);
      });

      await act(async () => {
        try {
          await result.current.remove();
        } catch {
          // expected
        }
      });

      expect(result.current.error?.code).toBe(PasspointErrorCode.REMOVE_FAILED);
      // isInstalled should not change on failure
      expect(result.current.isInstalled).toBe(true);
    });
  });

  describe("refresh", () => {
    it("manually refreshes status", async () => {
      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      // Simulate profile installed externally
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.isInstalled).toBe(true);
      expect(result.current.certificateInfo?.domain).toBe("hib.nova.xyz");
    });

    it("handles getCertificateInfo failure gracefully during refresh", async () => {
      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      // isInstalled works but getCertificateInfo fails
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockRejectedValue(new Error("keychain error"));

      await act(async () => {
        await result.current.refresh();
      });

      // Should still update isInstalled even if cert info fails
      expect(result.current.isInstalled).toBe(true);
    });
  });

  describe("app state listener", () => {
    it("refreshes when app comes to foreground", async () => {
      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      // Clear calls from initial mount
      mockNative.isInstalled.mockClear();

      // Simulate profile installed while app was in background
      mockNative.isInstalled.mockResolvedValue(true);
      mockNative.getCertificateInfo.mockResolvedValue(CERT_INFO_INSTALLED);

      // Fire foreground event
      await act(async () => {
        __emitAppState("active");
      });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(true);
      });
    });

    it("does not refresh on background/inactive state changes", async () => {
      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      mockNative.isInstalled.mockClear();

      await act(async () => {
        __emitAppState("background");
        __emitAppState("inactive");
      });

      // Should not have triggered a refresh
      expect(mockNative.isInstalled).not.toHaveBeenCalled();
    });

    it("removes its listener on unmount", async () => {
      const before = __appStateListenerCount();
      const { result, unmount } = renderHook(() => usePasspoint(), { wrapper });
      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });
      expect(__appStateListenerCount()).toBe(before + 1);

      unmount();
      expect(__appStateListenerCount()).toBe(before);
    });
  });

  describe("getRemoteStatus", () => {
    it("returns parsed status from the native bridge", async () => {
      mockNative.getRemoteStatus.mockResolvedValue(
        JSON.stringify({
          subscriberId: "sub-001",
          presetId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
          eapType: 13,
          expiresAt: "2027-01-15T10:30:00Z",
          active: true,
        }),
      );

      const { result } = renderHook(() => usePasspoint(), { wrapper });
      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      let status: Awaited<ReturnType<typeof result.current.getRemoteStatus>> | null =
        null;
      await act(async () => {
        status = await result.current.getRemoteStatus("sub-001");
      });

      expect(mockNative.getRemoteStatus).toHaveBeenCalledWith("sub-001");
      expect(status).toEqual({
        subscriberId: "sub-001",
        presetId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        eapType: 13,
        expiresAt: "2027-01-15T10:30:00Z",
        active: true,
      });
    });

    it("returns null when the server has no profile", async () => {
      mockNative.getRemoteStatus.mockResolvedValue("null");

      const { result } = renderHook(() => usePasspoint(), { wrapper });
      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      let status: Awaited<ReturnType<typeof result.current.getRemoteStatus>> | null =
        null;
      await act(async () => {
        status = await result.current.getRemoteStatus("sub-404");
      });

      expect(status).toBeNull();
    });

    it("sets error state and rethrows on native rejection", async () => {
      mockNative.getRemoteStatus.mockRejectedValue({
        code: "API_UNAUTHORIZED",
        message: "rejected",
      });

      const { result } = renderHook(() => usePasspoint(), { wrapper });
      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      await act(async () => {
        try {
          await result.current.getRemoteStatus("sub-001");
        } catch {
          // expected
        }
      });

      expect(result.current.error?.code).toBe(PasspointErrorCode.API_UNAUTHORIZED);
    });
  });
});
