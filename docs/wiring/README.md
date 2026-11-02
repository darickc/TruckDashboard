# Wiring

Status: **no diagrams yet** (Phase 7).

Every diagram here must:

- name each fuse rating, wire gauge and connection point
- route vehicle 12 V signals only through protected or opto-isolated inputs,
  never to Pi GPIO
- be reviewed and signed off by a person in
  [bench-log.md](../hardware/bench-log.md) **before** installation (see the
  [safety gates](../safety/assumptions.md#human-verification-gates))

Connecting anything to the DLC also needs the CAN termination question
([H1](../hardware/open-questions.md)) closed first.
