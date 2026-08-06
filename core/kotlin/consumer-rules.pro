# BouncyCastle is used reflectively by the JCA provider machinery.
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# HotspotConfigurator reaches @hide framework members by reflection when the
# running API level exposes them. Losing the names is handled (the reflection is
# best-effort) but keeping the SDK's own classes avoids surprises.
-keep class com.helium.passpoint.** { *; }
