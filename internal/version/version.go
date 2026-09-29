// Package version holds the version string of Actaira builds.
package version

// Version is "dev" in local builds. Release builds override it with
// -ldflags "-X github.com/actaira/actaira/internal/version.Version=<tag>".
var Version = "dev"
