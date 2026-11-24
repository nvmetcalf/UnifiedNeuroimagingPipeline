#!/usr/bin/env python3
"""
UNP_GUI - a local web GUI for running the UnifiedNeuroimagingPipeline (P2)
on multi-subject datasets through Slurm.

    python3 unp_gui.py                  # start, open browser
    python3 unp_gui.py --no-browser     # print URL only
    python3 unp_gui.py --port 9000
    python3 unp_gui.py --projects-home /gpfs/data/siegellab/UnifiedNeuroimagingPipeline
    python3 unp_gui.py --fake           # simulate Slurm (testing off-cluster)
    python3 unp_gui.py --selftest       # build a fake dataset in /tmp and serve it

Standard library only (numpy optional, for NIfTI montages).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.umask(0o002)

from unp_gui import config as _cfg          # noqa: E402
from unp_gui import server                   # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int)
    ap.add_argument("--host", default=None, help="bind address (default 127.0.0.1; use 0.0.0.0 with care)")
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--projects-home", help="override PROJECTS_HOME (root with SCRIPTS/Scans/Projects)")
    ap.add_argument("--env-script", help="bash PipelineEnvironment.sh sourced by jobs")
    ap.add_argument("--fake", action="store_true", help="simulate Slurm submissions")
    ap.add_argument("--selftest", action="store_true", help="create a fake dataset and serve it with --fake")
    ap.add_argument("--config", default=_cfg.CONFIG_PATH)
    args = ap.parse_args()

    if args.selftest:
        from unp_gui import selftest
        root = selftest.build_fake_tree()
        args.projects_home = root
        args.fake = True
        args.config = os.path.join(root, "gui_config.json")

    cfg = _cfg.Config(args.config)
    if args.projects_home:
        cfg.data["projects_home"] = os.path.abspath(args.projects_home)
        cfg.data["env_script"] = args.env_script or os.path.join(cfg.data["projects_home"], "PipelineEnvironment.sh")
        cfg.resolve()
    elif args.env_script:
        cfg.data["env_script"] = args.env_script
        cfg.resolve()
    if not os.path.isfile(cfg.path):
        try:
            cfg.save()          # persist defaults (never the --fake flag)
        except OSError as e:
            print(f"WARNING: could not write {cfg.path}: {e}", file=sys.stderr)
    if args.fake:
        cfg.data["fake_slurm"] = True
    if cfg.data.get("fake_slurm"):
        print("NOTE: fake_slurm is ON (from --fake or config.json/Settings): nothing will be submitted to Slurm.")

    if not os.path.isdir(cfg.projects_home):
        print(f"ERROR: PROJECTS_HOME {cfg.projects_home} does not exist. Use --projects-home.", file=sys.stderr)
        sys.exit(1)
    server.serve(cfg, host=args.host, port=args.port, open_browser=not args.no_browser)


if __name__ == "__main__":
    main()
