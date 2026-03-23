import { PasspointError } from "../errors";
import { PasspointErrorCode } from "../types";

describe("PasspointError", () => {
  it("sets name, code, and message", () => {
    const err = new PasspointError(
      PasspointErrorCode.PERMISSION_DENIED,
      "Location permission required",
    );

    expect(err).toBeInstanceOf(Error);
    expect(err).toBeInstanceOf(PasspointError);
    expect(err.name).toBe("PasspointError");
    expect(err.code).toBe(PasspointErrorCode.PERMISSION_DENIED);
    expect(err.message).toBe("Location permission required");
    expect(err.nativeError).toBeUndefined();
  });

  it("preserves the native error", () => {
    const native = new Error("underlying issue");
    const err = new PasspointError(PasspointErrorCode.UNKNOWN, "something broke", native);

    expect(err.nativeError).toBe(native);
  });

  describe("fromNative", () => {
    it("returns the same error if already a PasspointError", () => {
      const original = new PasspointError(PasspointErrorCode.API_ERROR, "bad response");

      expect(PasspointError.fromNative(original)).toBe(original);
    });

    it("wraps a native module rejection with a known code", () => {
      const nativeRejection = {
        code: "PERMISSION_DENIED",
        message: "Location permission denied",
      };

      const err = PasspointError.fromNative(nativeRejection);

      expect(err).toBeInstanceOf(PasspointError);
      expect(err.code).toBe(PasspointErrorCode.PERMISSION_DENIED);
      expect(err.message).toBe("Location permission denied");
      expect(err.nativeError).toBe(nativeRejection);
    });

    it("falls back to UNKNOWN for unrecognized codes", () => {
      const nativeRejection = {
        code: "SOME_RANDOM_CODE",
        message: "weird error",
      };

      const err = PasspointError.fromNative(nativeRejection);

      expect(err.code).toBe(PasspointErrorCode.UNKNOWN);
      expect(err.message).toBe("weird error");
    });

    it("handles undefined/null input", () => {
      const err = PasspointError.fromNative(undefined);

      expect(err.code).toBe(PasspointErrorCode.UNKNOWN);
      expect(err.message).toBe("An unknown error occurred");
    });

    it("handles plain string errors", () => {
      const err = PasspointError.fromNative("something failed");

      expect(err.code).toBe(PasspointErrorCode.UNKNOWN);
    });
  });
});
