# Offline Carbide Motion packages

Drop a `carbidemotion-<build>.deb` here to build without reaching Carbide 3D, or to pin an exact build. Anything in this directory is preferred over a download, and the highest build number wins unless `CARBIDE_MOTION_BUILD` in [build.conf](../build.conf) names one.

```bash
curl -O https://motion-pi.us-east-1.linodeobjects.com/carbidemotion-654.deb
mv carbidemotion-654.deb .
```

Packages are gitignored. Carbide Motion is proprietary software from Carbide 3D and is not redistributed by this repository.
