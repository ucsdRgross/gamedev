class_name ParticleSpec
extends Resource
## One KIND of particle, as data. Every particle in the game is described by one of these and
## simulated by ParticleEngine; kinds are .tres files (ember.tres, dust.tres), never code — the
## same rule FxStyle follows, so all visual-effect tuning stays in one place.

## Seconds a particle lives, and how much that varies per particle (0 = every one identical).
@export var lifetime : float = 1.2
@export_range(0.0, 1.0, 0.01) var lifetime_var : float = 0.4

## Launch speed along the emit direction, its variation, and how wide the cone spreads.
@export var speed : float = 18.0
@export_range(0.0, 1.0, 0.01) var speed_var : float = 0.5
@export_range(0.0, PI, 0.01) var spread : float = 0.6

## Art units per second squared. Negative y rises, which is what embers do.
@export var gravity : Vector2 = Vector2(0.0, -14.0)
## Fraction of velocity shed per second — what makes a rising ember slow and hang.
@export_range(0.0, 8.0, 0.05) var drag : float = 1.6

## Size in art units at birth and at death. Particles carry NO rotation: a rotating sprite is a
## rotating pixel grid, which the project's universal VFX rule forbids.
@export var size_start : float = 2.0
@export var size_end : float = 0.5

## Colour over life. Sampled by normalized age, so one gradient covers fade-out and colour shift.
@export var ramp : Gradient = null
