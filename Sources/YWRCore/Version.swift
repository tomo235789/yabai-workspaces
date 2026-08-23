/// The single source of truth for the ywr version. Bump this on each release and
/// tag the commit (e.g. `git tag v0.1.0`); the CLI (`ywr --version`) and the
/// menu-bar app both read it from here.
public enum YWRVersion {
    public static let current = "0.1.0"
}
