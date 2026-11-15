# AppArmor profile: complain-mode soak (INT-82)

`socket-proxy/apparmor.txt` ships in **complain mode**. This plan is how it
gets to enforce mode. Delete this file in the change that removes the
`complain` flag.

The operator runs every step on `smart`. Nothing here can run in CI: the
test suite only checks that the profile compiles and that the Supervisor's
one-top-level-profile rule holds.

## Facts the steps rely on

Read from the Supervisor source (`supervisor/apps/app.py`,
`supervisor/utils/apparmor.py`, `supervisor/docker/app.py`):

- The profile is loaded on add-on **install and update only**. Editing
  `apparmor.txt` has no effect until the add-on is reinstalled or updated;
  a restart is not enough.
- The top-level profile name is rewritten to the add-on slug, and the
  container runs with `apparmor=<slug>`. A local add-on's slug is
  `local_socket-proxy`, so HAProxy's child profile is
  `local_socket-proxy//haproxy`.
- A profile the host parser rejects fails the install or update, with the
  error in the Supervisor log. A profile that loads but denies something
  fails at runtime, and the add-on log only shows the symptom. The cause is
  in the host audit log.
- In complain mode, uncovered accesses are allowed and logged as
  `apparmor="ALLOWED"`. The `audit deny` rules in the HAProxy child still
  block and log as `apparmor="DENIED"`.

## Setup

1. Stop the production add-on. Both use `host_network` and port 2375.
2. Copy `socket-proxy/` from this branch to `/addons/socket-proxy/` on
   `smart` (Samba or SSH add-on). In Settings > Add-ons > Add-on store,
   use the menu to check for updates. It appears under "Local add-ons".
3. Install it, turn **Protection mode off**, and set the same options as
   production.
4. Start it. From a host shell (port 22222 or the console):

   ```sh
   docker inspect -f '{{.AppArmorProfile}}' addon_local_socket-proxy
   # expect: local_socket-proxy
   grep socket-proxy /sys/kernel/security/apparmor/profiles
   # expect both profiles, each marked (complain)
   ```

   If the first command prints `unconfined` or `docker-default`, the
   profile is not attached. Stop here and check the Supervisor log.

## Exercise

Run each of these at least once, and note the time you started:

- Dozzle connects, lists containers and streams logs for several minutes.
- Change `ALLOWED_CIDRS` to a valid allowlist, restart, and confirm that
  Dozzle still connects.
- Set `DISABLE_IPV6: false`, restart, then set it back.
- Set `ALLOWED_CIDRS` to a single invalid entry and start. The add-on
  should refuse to start, which runs the `finish` path. Then restore it.
- Stop and start from the UI. Reboot the host once.
- Leave it running under normal Dozzle use for **7 days**.

## Collect

```sh
journalctl _TRANSPORT=audit --since "<start time>" \
  | grep -E 'apparmor="(ALLOWED|DENIED)"' | grep socket-proxy
```

Paste the output into INT-82. Each `ALLOWED` line becomes a rule, or a
decision that the access should be denied. Any `DENIED` line from the
`haproxy` child means an `audit deny` rule hit something real. Look at it
before you go on.

After a rule change, reinstall the local add-on so the new profile loads,
then repeat Exercise. You are done when a full 7-day pass logs no
`ALLOWED` lines.

## Enforce

1. Remove `complain` from both `flags=(...)` lines and bump the version
   (`config.yaml`, `run`, CHANGELOG, AGENTS.md).
2. Reinstall the local copy and repeat Exercise. Expect zero `DENIED`
   lines, and Dozzle must work throughout.
3. Release. Users get the profile on update. The add-on's security rating
   goes up by one point for the custom profile.
4. Delete this plan in the same change.

## Rollback

- On `smart`: delete `/addons/socket-proxy/apparmor.txt` and reinstall.
  The Supervisor removes the stored profile when the file is gone.
- For released users: a patch release that restores `complain`, or removes
  the file. The profile only changes on update, so a fix needs a release.

## Known gaps in the draft

- The outer profile uses `file,` (all file access), like the official
  `dnsmasq` and example profiles. The confinement that matters is the
  `haproxy` child. The outer one can be tightened later if the soak log
  shows a small, stable set of accesses.
- The outer profile's capability list and the child's `/proc` and `/sys`
  reads are educated guesses. The soak confirms or trims them.
- The profile compiles with AppArmor parser 5.0.2 on the dev host. HAOS
  ships its own parser and abstractions. A parse error there shows up at
  install in step 3 of Setup.
- AppArmor cannot narrow what HAProxy sends over the Docker socket. Which
  API calls get through is still decided only by the ACLs in `haproxy.cfg`.
