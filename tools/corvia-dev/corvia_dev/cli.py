"""CLI entry point for corvia-dev."""

import click


@click.group()
def main() -> None:
    """Dev environment orchestration for corvia-workspace."""


@main.command()
def status() -> None:
    """Show service health and config summary."""
    click.echo("corvia-dev status: not yet implemented")


if __name__ == "__main__":
    main()
