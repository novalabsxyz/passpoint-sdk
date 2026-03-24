module.exports = {
  dependency: {
    platforms: {
      ios: {
        podspecPath: "./helium-passpoint-sdk.podspec",
      },
      android: {
        sourceDir: "./android",
        packageImportPath:
          "import com.helium.passpoint.PasspointSDKPackage;",
        packageInstance: "new PasspointSDKPackage()",
        // No C++/codegen — pure Kotlin module
        cmakeListsPath: null,
      },
    },
  },
};
