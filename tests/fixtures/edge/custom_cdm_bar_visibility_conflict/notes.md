# Custom CDM Bar Visibility Conflict

Pins v36 customBar compatibility normalization. Profiles created on the
options-overhaul branch could save multiple mutually-exclusive legacy custom
tracker visibility flags as true; v36 must collapse that to a single mode.
