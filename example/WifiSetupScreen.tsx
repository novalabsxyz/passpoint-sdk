/**
 * Example screen showing all SDK operations:
 * install, check status, view certificate info, and remove.
 */
import React from "react";
import {
  ActivityIndicator,
  Alert,
  SafeAreaView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import {
  usePasspoint,
  PasspointError,
  PasspointErrorCode,
} from "@helium/passpoint-sdk";

interface Props {
  userId: string;
}

function InfoRow({
  label,
  value,
}: {
  label: string;
  value: string | boolean | null | undefined;
}) {
  const display =
    value === null || value === undefined
      ? "—"
      : typeof value === "boolean"
        ? value
          ? "true"
          : "false"
        : value;
  return (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <Text
        style={styles.infoValue}
        numberOfLines={1}
        ellipsizeMode="middle"
      >
        {display}
      </Text>
    </View>
  );
}

export function WifiSetupScreen({ userId }: Props) {
  const {
    isInstalled,
    certificateInfo,
    install,
    remove,
    refresh,
    isLoading,
    error,
  } = usePasspoint();

  const handleInstall = async () => {
    try {
      await install(userId);
      Alert.alert("Success", "WiFi offload profile installed!");
    } catch (e) {
      if (e instanceof PasspointError) {
        switch (e.code) {
          case PasspointErrorCode.PERMISSION_DENIED:
            Alert.alert(
              "Permission Required",
              "Location permission is needed to install the WiFi profile. Please grant it in Settings.",
            );
            break;
          case PasspointErrorCode.PROFILE_INSTALL_CANCELLED:
            Alert.alert("Cancelled", "You cancelled the profile installation.");
            break;
          case PasspointErrorCode.API_UNAUTHORIZED:
            Alert.alert("Error", "Invalid API key. Contact support.");
            break;
          default:
            Alert.alert("Error", e.message);
        }
      }
    }
  };

  const handleRemove = async () => {
    Alert.alert(
      "Remove WiFi Profile",
      "This will disconnect you from Helium WiFi hotspots. Continue?",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: async () => {
            try {
              await remove();
              Alert.alert("Done", "WiFi profile has been removed.");
            } catch (e) {
              if (e instanceof PasspointError) {
                Alert.alert("Error", e.message);
              }
            }
          },
        },
      ],
    );
  };

  // Loading initial status
  if (isInstalled === null) {
    return (
      <SafeAreaView style={styles.container}>
        <ActivityIndicator size="large" />
        <Text style={styles.subtitle}>Checking WiFi status...</Text>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>WiFi Offload</Text>

        {isInstalled ? (
          <>
            <View style={styles.statusBadge}>
              <Text style={styles.statusText}>Active</Text>
            </View>
            <Text style={styles.subtitle}>
              You're connected to Helium WiFi hotspots automatically.
            </Text>

            <View style={styles.infoCard}>
              <InfoRow
                label="isInstalled"
                value={certificateInfo?.isInstalled}
              />
              <InfoRow label="domain" value={certificateInfo?.domain} />
              <InfoRow
                label="friendlyName"
                value={certificateInfo?.friendlyName}
              />
              <InfoRow label="subject" value={certificateInfo?.subject} />
              <InfoRow label="expiresAt" value={certificateInfo?.expiresAt} />
            </View>

            <TouchableOpacity
              style={[styles.button, styles.dangerButton]}
              onPress={handleRemove}
              disabled={isLoading}
            >
              <Text style={styles.buttonText}>
                {isLoading ? "Removing..." : "Remove WiFi Profile"}
              </Text>
            </TouchableOpacity>
          </>
        ) : (
          <>
            <Text style={styles.subtitle}>
              Enable automatic WiFi offload to connect to thousands of hotspots
              and save on data usage.
            </Text>

            <TouchableOpacity
              style={styles.button}
              onPress={handleInstall}
              disabled={isLoading}
            >
              {isLoading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.buttonText}>Enable WiFi Offload</Text>
              )}
            </TouchableOpacity>
          </>
        )}

        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>
              {error.code}: {error.message}
            </Text>
          </View>
        )}

        <TouchableOpacity
          style={styles.refreshButton}
          onPress={refresh}
          disabled={isLoading}
        >
          <Text style={styles.refreshText}>Refresh Status</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#fff",
  },
  content: {
    flex: 1,
    padding: 24,
    justifyContent: "center",
    alignItems: "center",
    gap: 16,
  },
  title: {
    fontSize: 28,
    fontWeight: "bold",
    color: "#1a1a1a",
  },
  subtitle: {
    fontSize: 16,
    color: "#666",
    textAlign: "center",
    lineHeight: 24,
  },
  infoCard: {
    width: "100%",
    backgroundColor: "#f8f8f8",
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 4,
  },
  infoRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "#e5e5e5",
    gap: 12,
  },
  infoLabel: {
    fontSize: 13,
    color: "#666",
    fontWeight: "500",
  },
  infoValue: {
    fontSize: 13,
    color: "#1a1a1a",
    fontFamily: "Menlo",
    flexShrink: 1,
    textAlign: "right",
  },
  statusBadge: {
    backgroundColor: "#e8f5e9",
    paddingHorizontal: 16,
    paddingVertical: 6,
    borderRadius: 20,
  },
  statusText: {
    color: "#2e7d32",
    fontWeight: "600",
  },
  button: {
    backgroundColor: "#4f46e5",
    paddingHorizontal: 32,
    paddingVertical: 16,
    borderRadius: 12,
    width: "100%",
    alignItems: "center",
    marginTop: 8,
  },
  dangerButton: {
    backgroundColor: "#dc2626",
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  refreshButton: {
    paddingVertical: 12,
  },
  refreshText: {
    color: "#4f46e5",
    fontSize: 14,
  },
  errorContainer: {
    backgroundColor: "#fef2f2",
    padding: 12,
    borderRadius: 8,
    width: "100%",
  },
  errorText: {
    color: "#dc2626",
    fontSize: 13,
  },
});
