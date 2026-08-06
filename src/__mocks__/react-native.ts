export const Platform = {
  OS: "ios" as string,
  select: (obj: any) => obj.ios,
};

const appStateListeners: Array<(state: string) => void> = [];

export const AppState = {
  currentState: "active",
  addEventListener: jest.fn((_type: string, listener: (state: string) => void) => {
    appStateListeners.push(listener);
    return {
      remove: jest.fn(() => {
        const idx = appStateListeners.indexOf(listener);
        if (idx >= 0) appStateListeners.splice(idx, 1);
      }),
    };
  }),
};

/**
 * Drive the AppState listeners from a test.
 *
 * Do NOT `jest.spyOn(AppState, "addEventListener")`: the property is already a
 * `jest.fn`, so `spyOn` hands back that same mock rather than wrapping it, and
 * the matching `mockRestore()` resets the module mock to a no-op returning
 * `undefined`. Every later test then throws in `PasspointProvider`'s cleanup
 * (`subscription.remove()` on undefined) — and Jest still reports them as
 * passing, because the throw surfaces only as a React console error.
 */
export function __emitAppState(state: string): void {
  for (const listener of [...appStateListeners]) listener(state);
}

export function __appStateListenerCount(): number {
  return appStateListeners.length;
}

// Mock NativeModules.HeliumPasspointSDK
export const NativeModules = {
  HeliumPasspointSDK: {
    configure: jest.fn(),
    install: jest.fn(),
    isInstalled: jest.fn(),
    getCertificateInfo: jest.fn(),
    getRemoteStatus: jest.fn(),
    remove: jest.fn(),
    debug: jest.fn(),
  },
};
