"""Project0 host-side infrastructure services (enrollment, operator, opnsense).

Making `infra` a real package (not a namespace package) ensures pytest imports
sub-package tests as `infra.<pkg>.tests.*`, so a package named `operator` is
never confused with Python's stdlib `operator` module.
"""
