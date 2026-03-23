/**
 * Example app demonstrating @helium/passpoint-sdk integration.
 *
 * This is the minimal code a partner needs to add WiFi offload to their app.
 */
import React from "react";
import { PasspointProvider } from "@helium/passpoint-sdk";
import { WifiSetupScreen } from "./WifiSetupScreen";

// Replace with your API key from the Helium partner dashboard
const HELIUM_API_KEY = "your-api-key-here";

export default function App() {
  return (
    <PasspointProvider
      config={{
        apiKey: HELIUM_API_KEY,
        // environment: 'development', // use 'production' (default) for release
      }}
    >
      <WifiSetupScreen userId="user-abc-123" />
    </PasspointProvider>
  );
}
