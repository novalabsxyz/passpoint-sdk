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

// Mock NativeModules.HeliumPasspointSDK
export const NativeModules = {
  HeliumPasspointSDK: {
    configure: jest.fn(),
    install: jest.fn(),
    isInstalled: jest.fn(),
    getCertificateInfo: jest.fn(),
    getRemoteStatus: jest.fn(),
    remove: jest.fn(),
  },
};
