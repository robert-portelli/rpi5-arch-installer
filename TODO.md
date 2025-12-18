# Project Notes — Status as of December 17, 2025

## Goal of the aborted attempt
I attempted to make Stage 10 (systemd-repart + formatting) fully testable
inside an **unprivileged container** without requiring a privileged runner
or device-mapper functionality. The intended design:

1. Run repart on a loopback device inside the container.
2. Detect partitions via sysfs when udev / by-partuuid was not available.
3. Manually create /dev/<disk>pN nodes using mknod.
4. Avoid using kpartx or device-mapper.
5. Use these synthetic nodes to run mkfs.vfat and Btrfs formatting.
6. Make the Stage 10 tests work in GitHub Actions without `--privileged`.

## Where things succeeded
- Loopback device creation from the host and passing via `--device` works.
- systemd-repart successfully writes the new GPT to the loop device.
- sysfs partition metadata becomes visible inside the test container
  (major/minor are correct for p1/p2).
- Manual mknod succeeds and creates matching device files.
- Test suite structure and config-node registration logic are solid.

## Where things failed
The synthetic device nodes created inside the container **are not usable**
for mkfs or any filesystem-level I/O:

- mkfs.vfat fails with: *“No such device or address”*
- Kernel does **not** associate the synthetic `/dev/loop0p1` with the actual
  loopback device → there is **no real block backend**.
- This is because only `/dev/loop0` exists naturally inside the container;
  its partition nodes **must be created by the kernel**, via udev/device-mapper,
  not userland `mknod`.
- We cannot force the kernel to register partitions without udev or dm.
- GitHub Actions containers do **not** permit privileged device-mapper usage.

## Clear conclusion
**You cannot fully simulate the required block-device semantics inside an
unprivileged container.**
Manual mknod is not sufficient; the kernel must know about the partition.

## Options for the future
1. **Run Stage 10 on the host (privileged) and test subsequent stages inside containers.**
   → Split tests into “host-required” and “container-safe”.

2. **Use a privileged GitHub Actions runner (needs self-hosted).**
   → Then udev + dm + loop-part scanning will work.

3. **Use kpartx/device-mapper inside a privileged container.**
   → But GitHub-hosted runners do not allow this.

4. **Refactor Stage 10 tests into integration tests, not unit tests.**
   → Fully acceptable for a partitioning stage.

## What to do next
- Decide on one of the strategies above.
- Remove the sysfs/mknod fallback once an official testing path is chosen.
- Keep the config[ESP_NODE]/[ROOT_NODE] logic — it *is* useful.

---

That’s all you need. This gives future-you:

- The objective
- The reasoning
- Where the approach broke down
- The next move

If you'd like, I can generate a polished version of this note tailored to your repo conventions or create the file directly as text you can commit.
