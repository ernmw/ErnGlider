# Glider

OpenMW mod that adds a glider when you double-jump outside.

Make sure you're playing on OpenMW 0.51+.

## Installing

Add `00 Core` and one of these to your data paths:
- `01 Dwemer Glider`
- `01 Dwemer Glider Hands-Free`
- `01 Racer Glider`

Add both `ErnGlider.omwaddon` and `ErnGlider.omwscripts`!

In your settings.cfg, **enable** these:

- [use-additional-anim-sources](https://openmw.readthedocs.io/en/stable/reference/modding/settings/game.html#use-additional-anim-sources)
- [smooth-animation-transitions](https://openmw.readthedocs.io/en/stable/reference/modding/settings/game.html#smooth-animation-transitions)
- [player-movement-ignores-animation](https://openmw.readthedocs.io/en/stable/reference/modding/settings/game.html#player-movement-ignores-animation)

If you have the OpenMW Camera set to "Move 360", the glider and shield won't render.

## Using Your Glider

Gliders only work while outside. While in an unreadied stance (your weapon is sheathed and you don't have your spellcasting hands out), do a double jump while not holding forward or backward. This will activate your glider, which drains fatigue. Tap your jump button again to put the glider away.

Alternatively, you may bind a dedicated key to toggle the Glider in the settings.

### Glider Quest Walkthrough

You can disable this quest completely in the mod settings. This is helpful if you're not playing on an English version of Morrowind.

1. Talk to a friendly [Acrobat](https://en.uesp.net/wiki/Category:Morrowind-Acrobat) to get a basic glider.
2. Talk to a friendly [Savant](https://en.uesp.net/wiki/Category:Morrowind-Savant) when you have at least 40 Acrobatics to upgrade your glider.
3. Talk to a friendly [Savant](https://en.uesp.net/wiki/Category:Morrowind-Savant) when you have at least 80 Acrobatics to upgrade your glider again.

If you're using `Ben's Skyships (OpenMW)`, you can instead just talk to a glider expert.

If you're on Vvardenfell, you can just talk to Louis Beauchamp.

<details>

<summary>Console Commands</summary>

You can enable the glider like this, too:

Basic glider: `setJournalIndex eg_glider 1`
Advanced glider: `setJournalIndex eg_glider 21`
Masterwork glider: `setJournalIndex eg_glider 31`

</details>

## Shield Surfing

While in an unreadied stance (your weapon is sheathed and you don't have your spellcasting hands out), do a double jump while holding backward. Shield surfing damages your shield, but you move faster while heading down-slope. Double-tap your jump button again to put your shield away.

Alternatively, you may bind a dedicated key to toggle Shield Surfing in the settings.

Lighter shields take less damage from falls, and accelerate and de-accelerate faster.
Heavier shields have a faster top speed.
Speed and Athletics contribute to your overall surfing speed.

## Credits

Erin coded this, but this wouldn't have been possible without the help of a lot of people. Special thanks to Dubious, Semaro, SahJop, Greatness7, S3ctor, Sergey Rudyi, and the rest of the OpenMW modding community.

### Sounds

- Wind 1 Loop by jasoneweber -- https://freesound.org/s/179110/ -- License: Attribution 3.0
- Breath In by mooncubedesign -- https://freesound.org/s/319247/ -- License: Creative Commons 0
- Gravel Road by seth-m -- https://freesound.org/people/seth-m/sounds/341069/ -- License: Creative Commons 0
- Landing On The Ground [2] by SoundDesignForYou -- https://freesound.org/people/SoundDesignForYou/sounds/646660/ -- License: Creative Commons 0
- up draft with more wind.wav by SahJop, used with explicit permission.
- Dwemer Glider/equip glider.wav by SahJop, used with explicit permission.
- Racer Glider/equip glider.wav by SahJop, used with explicit permission.
- trick sting.wav by SahJop, used with explicit permission.
- landing soft.wav by SahJop, used with explicit permission.
- landing hard.wav by SahJop, used with explicit permission.

### Meshes & Textures

- Dwemer Glider by Semaro, used with explicit permission.
- Racer Glider by Dubious, used with explicit permission.
- Textures by Wareya, used with explicit permission.
- Dust cloud by Kronbits -- https://kronbits.itch.io/particle-pack -- License: Creative Commons 0

## Animations

- openmw-animated-levitation -- https://gitlab.com/fallchildren/openmw-animated-levitation -- License: GPL
- Racer Glider animation by Dubious, used with explicit permission.
- Shield Surfing animation by Dubious, used with explicit permission.

### Third-Party Code

- openmw-animated-levitation -- https://gitlab.com/fallchildren/openmw-animated-levitation -- License: GPL
- PCP-OpenMW by Qlonever -- https://github.com/Qlonever/PCP-OpenMW) -- License: MIT
