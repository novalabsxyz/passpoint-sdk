import { act, renderHook, waitFor } from "@testing-library/react-native";
import type React from "react";
import { AppState, Platform } from "react-native";
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
        installResult = await result.current.install("user-abc");
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
          await result.current.install("user-abc");
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
          await result.current.install("user-abc");
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
        await result.current.install("user-abc");
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
      const listeners: Array<(state: string) => void> = [];
      const addEventSpy = jest
        .spyOn(AppState, "addEventListener")
        .mockImplementation((_type, listener) => {
          listeners.push(listener as (state: string) => void);
          return { remove: jest.fn() } as any;
        });

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
        for (const l of listeners) l("active");
      });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(true);
      });

      addEventSpy.mockRestore();
    });

    it("does not refresh on background/inactive state changes", async () => {
      const listeners: Array<(state: string) => void> = [];
      const addEventSpy = jest
        .spyOn(AppState, "addEventListener")
        .mockImplementation((_type, listener) => {
          listeners.push(listener as (state: string) => void);
          return { remove: jest.fn() } as any;
        });

      const { result } = renderHook(() => usePasspoint(), { wrapper });

      await waitFor(() => {
        expect(result.current.isInstalled).toBe(false);
      });

      mockNative.isInstalled.mockClear();

      await act(async () => {
        for (const l of listeners) l("background");
        for (const l of listeners) l("inactive");
      });

      // Should not have triggered a refresh
      expect(mockNative.isInstalled).not.toHaveBeenCalled();

      addEventSpy.mockRestore();
    });
  });
});
