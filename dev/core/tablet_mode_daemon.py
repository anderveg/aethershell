#!/usr/bin/env python3
"""Shim de compatibilité : la gestion du mode tablette est désormais portée dans `as-core tablet-mode`."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AS_CORE = os.path.join(HERE, "as-core")
os.execv(AS_CORE, [AS_CORE, "tablet-mode", *sys.argv[1:]])
