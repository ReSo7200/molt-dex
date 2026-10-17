#!/usr/bin/env python3
# manifest-summary.py - Stage B: turn AndroidManifest.xml into an attack-surface summary.
#
# Usage:
#   python3 -I manifest-summary.py <apktool-decoded-dir>
#
# apktool already decodes AndroidManifest.xml into plain text XML, so this just parses that file
# (no aapt, no binary-xml decoding needed). It prints the facts that decide where an app can be
# poked from the outside:
#   - package, min/target SDK
#   - debuggable, usesCleartextTraffic, networkSecurityConfig, allowBackup
#   - exported activities/services/receivers/providers, with the permission that guards them
#     (a component is exported if android:exported="true", OR it has an intent-filter and does
#      not set android:exported="false" - the classic implicitly-exported case)
#   - custom permissions declared, and their protectionLevel
#   - notable requested permissions
#   - deep-link schemes and hosts (intent-filters with a data scheme)
#   - content-provider authorities and grantUriPermissions
#
# Attack-surface items are marked with [*]. An exported component with no permission, a provider
# that grants URI permissions, a debuggable build, or cleartext traffic each widen it.
#
# Manual equivalent:
#   less <decoded>/AndroidManifest.xml   and read for exported=, intent-filter, permission, data
#
# Fail-soft: missing or unreadable manifest is reported, not fatal. Uses only the stdlib.

import os
import sys
import xml.etree.ElementTree as ET

A = '{http://schemas.android.com/apk/res/android}'   # android: namespace


def attr(el, name):
    return el.get(A + name)


def is_exported(el):
    exp = attr(el, 'exported')
    if exp is not None:
        return exp == 'true'
    # no explicit exported: implicitly exported iff it has an intent-filter
    return el.find('intent-filter') is not None


def comp_line(el, kind):
    name = attr(el, 'name') or '?'
    perm = attr(el, 'permission')
    exported = is_exported(el)
    flag = '[*]' if exported and not perm else '   '
    extra = []
    if perm:
        extra.append('perm=%s' % perm)
    if attr(el, 'exported') is None and el.find('intent-filter') is not None:
        extra.append('implicitly-exported')
    tail = ('  (' + ', '.join(extra) + ')') if extra else ''
    return '  %s %-9s %s%s' % (flag, kind, name, tail)


def deeplinks(app):
    out = []
    for comp in list(app):
        for intf in comp.findall('intent-filter'):
            for data in intf.findall('data'):
                scheme = attr(data, 'scheme')
                host = attr(data, 'host')
                path = attr(data, 'pathPrefix') or attr(data, 'path') or attr(data, 'pathPattern')
                if scheme:
                    s = '%s://' % scheme
                    if host:
                        s += host
                    if path:
                        s += path
                    out.append((attr(comp, 'name') or '?', s))
    return out


def main():
    if len(sys.argv) < 2:
        print("usage: manifest-summary.py <apktool-decoded-dir>", file=sys.stderr)
        return 2
    root = sys.argv[1]
    man = root if root.endswith('.xml') else os.path.join(root, 'AndroidManifest.xml')
    if not os.path.isfile(man):
        print("ERROR: no AndroidManifest.xml at %s (decode with apktool first)" % man, file=sys.stderr)
        return 2
    try:
        tree = ET.parse(man)
    except Exception as e:
        print("ERROR: cannot parse manifest: %s" % e, file=sys.stderr)
        return 2
    rootel = tree.getroot()
    app = rootel.find('application')

    print("== package ==")
    print("  package: %s" % rootel.get('package'))
    uses_sdk = rootel.find('uses-sdk')
    if uses_sdk is not None:
        print("  minSdk: %s  targetSdk: %s" % (attr(uses_sdk, 'minSdkVersion'), attr(uses_sdk, 'targetSdkVersion')))
    print("  versionCode: %s  versionName: %s" % (rootel.get(A + 'versionCode'), rootel.get(A + 'versionName')))

    if app is not None:
        print("\n== application flags ==")
        for f in ('debuggable', 'usesCleartextTraffic', 'allowBackup', 'networkSecurityConfig'):
            v = attr(app, f)
            if v is not None:
                mark = ''
                if f == 'debuggable' and v == 'true':
                    mark = '  [*] debuggable build'
                if f == 'usesCleartextTraffic' and v == 'true':
                    mark = '  [*] cleartext allowed'
                if f == 'allowBackup' and v == 'true':
                    mark = '  [*] backups allowed'
                print("  %s = %s%s" % (f, v, mark))

    # permissions
    declared = rootel.findall('permission')
    if declared:
        print("\n== custom permissions declared ==")
        for p in declared:
            print("  %s  protectionLevel=%s" % (attr(p, 'name'), attr(p, 'protectionLevel')))

    uses = [attr(p, 'name') for p in rootel.findall('uses-permission')]
    notable = [u for u in uses if u and any(k in u for k in (
        'SYSTEM_ALERT_WINDOW', 'WRITE_EXTERNAL', 'READ_EXTERNAL', 'MANAGE_EXTERNAL',
        'READ_SMS', 'RECEIVE_SMS', 'READ_CONTACTS', 'ACCESS_FINE_LOCATION', 'RECORD_AUDIO',
        'CAMERA', 'READ_PHONE_STATE', 'QUERY_ALL_PACKAGES', 'REQUEST_INSTALL_PACKAGES',
        'BIND_ACCESSIBILITY', 'PACKAGE_USAGE_STATS', 'INTERNET'))]
    if notable:
        print("\n== notable requested permissions ==")
        for u in notable:
            print("  %s" % u)

    # components
    if app is not None:
        for kind, tag in (('activity', 'activity'), ('activity-alias', 'activity-alias'),
                          ('service', 'service'), ('receiver', 'receiver'), ('provider', 'provider')):
            comps = app.findall(tag)
            exported = [c for c in comps if is_exported(c)]
            if exported:
                print("\n== exported %s(s) ==  ([*] = exported with no permission)" % kind)
                for c in exported:
                    print(comp_line(c, kind))

        provs = app.findall('provider')
        if provs:
            print("\n== content providers ==")
            for p in provs:
                auth = attr(p, 'authorities')
                grant = attr(p, 'grantUriPermissions')
                mark = '  [*] grants URI permissions' if grant == 'true' else ''
                print("  authority=%s exported=%s%s" % (auth, is_exported(p), mark))

    dl = deeplinks(app) if app is not None else []
    if dl:
        print("\n== deep links (scheme/host) ==")
        seen = set()
        for comp, uri in dl:
            if uri in seen:
                continue
            seen.add(uri)
            print("  [*] %s   (%s)" % (uri, comp))

    print("\nnote: [*] marks widen the attack surface. Exported-and-unprotected components, "
          "URI-granting providers, deep links, debuggable and cleartext are the usual first stops.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
