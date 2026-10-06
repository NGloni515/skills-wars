from posekit import add_action, mirror, rot, with_pose


def build_animations(rig):
    idle = {
        "spine": rot(x=4), "chest": rot(x=2), "head": rot(x=-4),
        "upper_arm.L": rot(y=-6), "upper_arm.R": rot(y=6),
        "forearm.L": rot(x=-12), "forearm.R": rot(x=-15),
        "thigh.L": rot(y=-3), "thigh.R": rot(y=3),
    }
    breathe = with_pose(
        idle, spine=rot(x=3), chest=rot(x=-1), head=rot(x=-2),
        upper_arm_L=rot(y=-9), upper_arm_R=rot(y=9),
        forearm_L=rot(x=-16), forearm_R=rot(x=-19), hips=rot(loc=(0, 0, 0.012)),
    )
    add_action(rig, "idle", [(0, idle), (30, breathe), (60, idle)], loop=True)

    lean = {"spine": rot(x=10), "chest": rot(x=4, z=8), "head": rot(x=-12)}
    contact = with_pose(
        lean,
        thigh_L=rot(x=-38), shin_L=rot(x=10), foot_L=rot(x=-15),
        thigh_R=rot(x=28), shin_R=rot(x=45), foot_R=rot(x=20),
        upper_arm_L=rot(x=30, y=-6), forearm_L=rot(x=-30),
        upper_arm_R=rot(x=-35, y=6), forearm_R=rot(x=-40),
        hips=rot(z=-6, loc=(0, 0, -0.03)),
    )
    passing = with_pose(
        lean,
        chest=rot(x=4),
        thigh_L=rot(x=-5), shin_L=rot(x=5),
        thigh_R=rot(x=-20), shin_R=rot(x=80), foot_R=rot(x=10),
        upper_arm_L=rot(x=5, y=-6), forearm_L=rot(x=-35),
        upper_arm_R=rot(x=-5, y=6), forearm_R=rot(x=-35),
        hips=rot(loc=(0, 0, 0.06)),
    )
    add_action(rig, "run", [
        (0, contact), (5, passing), (10, mirror(contact)), (15, mirror(passing)), (20, contact),
    ], loop=True)

    windup = with_pose(
        idle,
        spine=rot(z=-10), chest=rot(x=-4, z=-28),
        upper_arm_R=rot(x=55, y=25), forearm_R=rot(x=-70), hand_R=rot(x=-20),
        upper_arm_L=rot(x=-30, y=-15), forearm_L=rot(x=-30),
        thigh_L=rot(x=-15), thigh_R=rot(x=12), hips=rot(loc=(0, 0, -0.03)),
    )
    release = with_pose(
        idle,
        spine=rot(x=6, z=8), chest=rot(x=10, z=22),
        upper_arm_R=rot(x=-85), forearm_R=rot(x=-5),
        upper_arm_L=rot(x=25, y=-10), forearm_L=rot(x=-20),
        thigh_L=rot(x=-25), thigh_R=rot(x=15), shin_R=rot(x=20),
        hips=rot(loc=(0, -0.06, -0.04)),
    )
    follow = with_pose(
        release, chest=rot(x=12, z=26), upper_arm_R=rot(x=-70, y=-12), forearm_R=rot(x=-10),
        hips=rot(loc=(0, -0.08, -0.05)),
    )
    ready = with_pose(idle, chest=rot(z=6), upper_arm_R=rot(x=-45), forearm_R=rot(x=-25))
    add_action(rig, "hook_cast", [(0, idle), (7, windup), (9, release), (13, follow), (18, ready)])

    crank_a = {
        "spine": rot(x=-6), "head": rot(x=4),
        "upper_arm.R": rot(x=-60), "forearm.R": rot(x=-20),
        "upper_arm.L": rot(x=-30, y=20), "forearm.L": rot(x=-70),
        "thigh.L": rot(x=-15), "thigh.R": rot(x=10), "hips": rot(loc=(0, 0, -0.02)),
    }
    crank_b = with_pose(crank_a, upper_arm_L=rot(x=-50, y=25), forearm_L=rot(x=-45), hips=rot(loc=(0, 0, -0.035)))
    add_action(rig, "reel", [(0, crank_a), (6, crank_b), (12, crank_a)], loop=True)

    limp = {
        "root": rot(x=-15), "spine": rot(x=-25), "chest": rot(x=-10), "head": rot(x=-25),
        "upper_arm.L": rot(x=-150, y=-20), "upper_arm.R": rot(x=-140, y=20),
        "forearm.L": rot(x=-20), "forearm.R": rot(x=-20),
        "thigh.L": rot(x=-35), "thigh.R": rot(x=-25), "shin.L": rot(x=30), "shin.R": rot(x=40),
    }
    flail = with_pose(
        limp, upper_arm_L=rot(x=-130, y=-25), upper_arm_R=rot(x=-160, y=15),
        thigh_L=rot(x=-25), thigh_R=rot(x=-40),
    )
    add_action(rig, "dragged", [(0, limp), (8, flail), (16, limp)], loop=True)

    struck = with_pose(
        idle, chest=rot(x=-15), head=rot(x=-20),
        upper_arm_L=rot(y=-40), upper_arm_R=rot(y=40), hips=rot(loc=(0, 0, -0.05)),
    )
    buckle = with_pose(
        struck, root=rot(x=-35), thigh_L=rot(x=-30), thigh_R=rot(x=-30),
        shin_L=rot(x=40), shin_R=rot(x=40), hips=rot(loc=(0, 0, -0.1)),
    )
    down = {
        "root": rot(x=-88), "head": rot(x=-10),
        "upper_arm.L": rot(y=-70), "upper_arm.R": rot(y=70),
        "thigh.L": rot(x=-20, y=-8), "thigh.R": rot(x=-20, y=8), "shin.L": rot(x=20), "shin.R": rot(x=20),
    }
    bounce = with_pose(down, root=rot(x=-82))
    rest = with_pose(down, root=rot(x=-90), upper_arm_L=rot(y=-75), upper_arm_R=rot(y=75))
    add_action(rig, "death", [(0, idle), (6, struck), (14, buckle), (22, down), (28, bounce), (36, rest)])

    crouch = {
        "hips": rot(loc=(0, 0, -0.35)), "spine": rot(x=30),
        "thigh.L": rot(x=-70), "thigh.R": rot(x=-70), "shin.L": rot(x=110), "shin.R": rot(x=110),
        "foot.L": rot(x=-40), "foot.R": rot(x=-40),
        "upper_arm.L": rot(x=-30), "upper_arm.R": rot(x=-30), "forearm.L": rot(x=-40), "forearm.R": rot(x=-40),
    }
    rising = {
        "hips": rot(loc=(0, 0, -0.12)), "spine": rot(x=10),
        "thigh.L": rot(x=-30), "thigh.R": rot(x=-30), "shin.L": rot(x=50), "shin.R": rot(x=50),
        "foot.L": rot(x=-20), "foot.R": rot(x=-20),
        "upper_arm.L": rot(y=-60), "upper_arm.R": rot(y=60),
    }
    arms_up = with_pose(
        idle, chest=rot(x=-8), head=rot(x=-10),
        upper_arm_L=rot(y=-100), upper_arm_R=rot(y=100), hips=rot(loc=(0, 0, 0.04)),
    )
    add_action(rig, "spawn", [(0, crouch), (6, rising), (12, arms_up), (18, idle)])

    arms_out = with_pose(
        idle, chest=rot(x=-8), head=rot(x=-12),
        upper_arm_L=rot(x=-20, y=-50), upper_arm_R=rot(x=-20, y=50),
        forearm_L=rot(x=-60), forearm_R=rot(x=-60),
    )
    slap = with_pose(
        idle, chest=rot(x=6),
        upper_arm_L=rot(x=-35, y=15), upper_arm_R=rot(x=-35, y=-15),
        forearm_L=rot(x=-55), forearm_R=rot(x=-55), hips=rot(loc=(0, 0, -0.03)),
    )
    flex = with_pose(
        idle, chest=rot(x=-10), head=rot(x=-15),
        upper_arm_L=rot(y=-120), upper_arm_R=rot(y=120),
        forearm_L=rot(x=-40), forearm_R=rot(x=-40),
    )
    add_action(rig, "taunt", [
        (0, idle), (8, arms_out), (14, slap), (20, arms_out), (26, slap), (34, flex), (45, idle),
    ])

