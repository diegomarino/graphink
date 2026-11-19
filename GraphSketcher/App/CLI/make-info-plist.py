#!/usr/bin/env python3
"""Write graphink's Info.plist from the app's, for the graphink target's "Make Info.plist" build phase.

OmniFoundation starts from the main bundle's Info.plist: it needs OFRegistrations (the app's preference
defaults), a copyright that contains a year and its own OFControllerClass. The tool keeps only those from
the app's Info.plist, so it registers the same defaults under its own identifier
(com.diegomarino.Graphink.cli) and never declares document types, UTIs, URL schemes or services: it cannot
claim .graphink files. Xcode expands the $(...) settings and embeds the result in the executable
(__TEXT,__info_plist).

Usage: make-info-plist.py APP_INFO_PLIST OUTPUT
"""
import plistlib
import sys

KEPT = ("CFBundleDevelopmentRegion", "CFBundleInfoDictionaryVersion", "NSHumanReadableCopyright", "OFRegistrations")

if len(sys.argv) != 3:
    sys.exit(__doc__)
with open(sys.argv[1], "rb") as source:
    app = plistlib.load(source)
info = {key: app[key] for key in KEPT}
info.update(
    CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)",
    CFBundleName="graphink",
    CFBundleExecutable="$(EXECUTABLE_NAME)",
    CFBundleShortVersionString="$(MARKETING_VERSION)",
    CFBundleVersion="$(CURRENT_PROJECT_VERSION)",
    LSMinimumSystemVersion="$(MACOSX_DEPLOYMENT_TARGET)",
    NSPrincipalClass="NSApplication",
    OFControllerClass="GICController",
)
with open(sys.argv[2], "wb") as output:
    plistlib.dump(info, output)
