# Spike: plugin/host shared-framework type identity

Throwaway (see mattpocock-skills:prototype). Not part of the real app.

**Question:** can a separately-built, separately-signed plugin bundle, with
no knowledge of the host's file layout, resolve Swift protocol/type
identity correctly against the host's already-loaded copy of a shared
framework (MTatsPluginKit)?

**Verdict: yes**, confirmed empirically. See ADR-0005 in docs/adr/ for the
validated decision this unblocks. Rebuild with:

```
swiftc -emit-library -emit-module -module-name MTatsPluginKit -o build/libMTatsPluginKit.dylib \
  -emit-module-path build/ kit/MTatsPluginKit.swift -Xlinker -install_name -Xlinker @rpath/libMTatsPluginKit.dylib
swiftc -I build -L build -lMTatsPluginKit host/main.swift -o build/Host -Xlinker -rpath -Xlinker @executable_path
swiftc -emit-library -module-name Plugin -I build -L build -lMTatsPluginKit plugin/PluginMain.swift \
  -o Plugin.bundle/Contents/MacOS/Plugin -Xlinker -rpath -Xlinker /nonexistent/thirdparty/path
cp plugin/Info.plist Plugin.bundle/Contents/Info.plist
DYLD_PRINT_LIBRARIES=1 build/Host "$PWD/Plugin.bundle"
```

Key finding: dyld matches a dependency by its install-name *string* against
already-loaded images before trying to resolve a file path via the loading
image's own rpaths. The plugin's rpath pointed at `/nonexistent/thirdparty/path`
and it still worked, because the install-name string matched.
