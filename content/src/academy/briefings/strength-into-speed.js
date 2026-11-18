// CONTENT: needs expert review (strength and conditioning coach / sports scientist)
export default {
  id: 'strength-into-speed',
  topic: 'strength',
  title: 'Turning strength into speed',
  dek: 'You got stronger and your speed didn’t follow. That isn’t a failure — it’s a missing bridge, and you can build it.',
  insight: 'strengthNotSpeed',
  why: 'Your strength work went up by {strengthGain}, but your speed tests show {sprintChange}.',
  chapters: [
    {
      title: 'The gap between strong and fast',
      blocks: [
        {
          p: 'You’ve done the work. Your lifts have climbed steadily, you move heavier things with better form than you did a couple of months ago, and you feel more solid and stable. Then you test your speed, or a {event} asks for one explosive moment, and nothing has changed. Same time on the clock, same feeling of arriving a fraction late. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
          variants: {
            field: 'You’ve done the work. Your lifts have climbed steadily, you move heavier things with better form than you did a couple of months ago, and you feel more solid in contact. Then you line up for a sprint test, or you chase a ball played over the top in a game, and nothing has changed. Same time, same feeling of the defender staying on your shoulder. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            court: 'You’ve done the work. Your lifts have climbed steadily and you feel more solid when you get bumped under the basket or land from a block. Then you try to beat your defender off the dribble, or test your jump against the wall, and nothing has changed. The first step is the same, the reach is the same, and the defender still slides across in time. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            batBall: 'You’ve done the work. Your lifts have climbed steadily and you feel stronger through your legs and trunk. Then you step into the cage, or onto the mound, and the numbers haven’t moved: the same bat speed, the same exit velocity, the same reading on the radar gun, the same time from home to first. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            racket: 'You’ve done the work. Your lifts have climbed steadily and you feel stronger and more stable. Then you play a point and you are still a fraction late to the drop shot, the wide forehand or the shuttle in the back corner, and your serve has not gained any pace. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            endurance: 'You’ve done the work. Your lifts have climbed steadily and you feel stronger and more robust. Then you race, and the explosive parts haven’t changed: the dive off the blocks, the push off the wall, the first strokes of a rowing start, the sprint for the line or the surge on a climb. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            track: 'You’ve done the work. Your lifts have climbed steadily and you move heavier things with better form than a couple of months ago. Then you settle into the blocks, or hit the board, or step into the circle, and the clock or the tape measure says the same thing it said before. It is one of the most common frustrations in youth athletics, and it has a clear explanation.',
            combat: 'You’ve done the work. Your lifts have climbed steadily and you feel stronger in the clinch or on the grip. Then you shoot for a takedown, attack with a lunge or try to snap in for a throw, and your opponent still sees it coming and gets out of the way. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            artistic: 'You’ve done the work. Your strength has climbed steadily and you feel more solid in your landings and holds. Then you tumble, vault or leap, and the height and snap haven’t changed: the same rebound off the floor, the same amplitude in your jumps. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
            precision: 'You’ve done the work. You are stronger and more stable than a couple of months ago. If your sport is golf, you might have expected more clubhead speed and distance; it hasn’t come. In archery or shooting, speed matters less, but you may have hoped for more control late in a long day. It is a common frustration, and it has a clear explanation.',
            strength: 'You’ve done the work. Your strength has climbed steadily and grinding through a heavy effort feels easier than it used to. But the fast lifts haven’t followed: you are not getting under the bar any quicker, the bar slows in the same spot, and the attempts that need snap still fail. It is one of the most common frustrations for young lifters, and it has a clear explanation.',
            board: 'You’ve done the work. Your lifts have climbed steadily and you feel stronger and more solid. Then you try to pop higher off a ramp, explode out of the start gate, pop up faster on a wave or make a dynamic move on a boulder problem, and nothing has changed. It is one of the most common frustrations in youth sport, and it has a clear explanation.',
          },
        },
        { p: 'Strength and speed are related, but they are not the same quality. Getting stronger raises the ceiling on how much force your muscles can produce. Speed depends on how much of that force you can apply in the tiny window your sport actually gives you. Those are two different questions, and training answers the one you ask it.' },
        { yourData: 'strengthVsSprint' },
        { h: 'The clock you’re racing is tiny' },
        {
          p: 'Most explosive movements in sport happen in a fraction of a second. When you sprint at top speed, each foot is on the ground for roughly a tenth of a second; in the first steps of a start it stays down longer, but still only briefly. A take-off, a throw, a swing or a strike is over almost as fast. A slow, heavy lift is different: you can take your time to build force, and the biggest effort arrives well after a fast movement would already be finished.',
          variants: {
            batBall: 'Most explosive movements in sport happen in a fraction of a second, and hitting is one of the fastest. From the moment the swing starts to contact, a hitter has a tiny window, and a pitcher’s arm accelerates in less time than it takes to blink. Base running is similar: each foot touches the ground only briefly. A slow, heavy lift is different: you can take your time to build force, and the biggest effort arrives well after a swing or a throw would already be over.',
            racket: 'Most explosive movements in sport happen in a fraction of a second. The split step and push towards the ball are over in a moment, and the racket head accelerates through contact faster still. A slow, heavy lift is different: you can take your time to build force, and the biggest effort arrives well after you would already need to be moving towards the shot.',
            combat: 'Most explosive movements in sport happen in a fraction of a second, and in combat sports the window is set by your opponent. A takedown shot, a fencing lunge or a judo entry works only if it lands before they react. A slow, heavy lift is different: you can take your time to build force, and the biggest effort arrives well after your opponent would already have moved.',
            precision: 'In golf, the downswing lasts only a fraction of a second, and clubhead speed comes from how quickly force builds from the ground up through the hips, trunk and arms in that brief window. A slow, heavy lift is different: you can take your time to build force. In archery and shooting, the goal is not speed but stillness under fatigue, so strength serves control rather than snap — a different bridge, but the same principle of training the quality you need.',
            strength: 'In the snatch and the clean and jerk, the decisive moment — the final explosive push and the drop under the bar — takes a fraction of a second. Even in powerlifting, a lift that moves fast through the hard part is more likely to succeed. A slow, grinding effort is different: you can take your time to build force, and the biggest push arrives well after the bar should already have been travelling.',
          },
        },
        { p: 'Sports scientists call the speed at which you build force your rate of force development. Think of two athletes who can both produce the same maximum push. One reaches it quickly; the other gets there slowly. On a slow lift they look identical. In a fast movement, the quick one wins, because the slow one never gets to use most of what they have before the moment has passed.' },
        { p: 'There is a second reason your speed may be stuck. Hard strength training leaves your muscles carrying some fatigue for a day or two, and if your speed is always tested or used on top of that, it can hide real progress. Some athletes even feel a little slower in the middle of a heavy block. Often the speed shows up later, once the hard work eases and the body freshens up.' },
        { quote: 'Strength is the size of the engine. Speed is how much of it you can use in a fraction of a second.' },
        { p: 'None of this means strength work was wasted. A stronger athlete has more to draw on, tolerates the forces of sprinting, jumping, landing and changing direction better, and is generally more robust. Research on young athletes, including a major international consensus statement, supports supervised strength training as safe and effective for teenagers when it is coached well and progressed sensibly. The point is narrower: strength is a foundation, and speed is built on top of it, not inside it.' },
      ],
    },
    {
      title: 'Building the bridge',
      blocks: [
        { p: 'Coaches talk about a bridge between the gym and the sport, and the image fits. On one side is force you can produce slowly. On the other is force you can produce fast, in the shapes and directions your sport uses. Power work and plyometrics are the planks across. They teach your nervous system to switch muscles on quickly and to use the springiness of tendons rather than grinding through every movement.' },
        { h: 'Fast means fast' },
        { p: 'The single rule that matters most here is intent. A jump, a throw, a bound or a swing only builds speed if you do it as explosively as you can, every time. Moving a light object lazily trains you to be slow with a light object. Your coach may use jumps, hops, bounds, medicine-ball throws or light, fast lifts; whatever the tool, the quality is the point. If you can’t do it sharp, it isn’t doing its job.' },
        { p: 'That is why good programmes put power and speed work early in a session, after a proper warm-up and before anything that tires you. Your nervous system is freshest then. Ten minutes of crisp, fast work does more for speed than forty minutes of sloppy jumps at the end of a hard practice, when your legs are heavy and every landing is a little softer and slower than the last.' },
        { p: 'Landings matter as much as take-offs. A good jump starts with a quiet, controlled landing: knees tracking over your toes, hips back, chest up, no collapsing inwards. Those landings protect your knees and teach you to absorb force and send it straight back out. As you get better, the time you spend on the ground in hops and bounds shrinks, which is exactly the quality fast feet, take-offs and changes of direction need.' },
        { h: 'Speed is a skill' },
        { p: 'Here is the part many athletes skip: the best way to get faster at the fast thing your sport asks for is to do it, at or near full speed, regularly. Speed is a skill as much as a capacity. Your brain has to coordinate dozens of muscles in the right order at a pace that leaves no time for thinking, and it only learns that pattern by rehearsing it at the real speed. Doing the movement slowly, even lots of it, teaches a different pattern.' },
        { p: 'That also means full rest between fast efforts. If you start the next one before you have recovered, you are no longer practising top speed; you are practising being tired. Sprint and power coaches give long recoveries for this reason, and it can feel strange to stand around between efforts. Walk back slowly, breathe, chat if you like. When you feel genuinely ready to go again at full quality, go. The rest is part of the work.' },
        {
          example: {
            title: 'A tale of two wingers',
            body: 'Picture two wingers on the same team who both started strength training in the autumn. The first adds hard conditioning runs on top, finishing every session with shuttles until she is gasping. The second keeps her strength work, adds a short block of sharp jumps and a few flying sprints with long rests at the start of a couple of sessions each week, and leaves the shuttles to team practice. By spring both are stronger. Only the second is clearly quicker to the ball, because only she trained speed at speed.',
            variants: {
              court: {
                title: 'Two guards, one summer',
                body: 'Picture two basketball guards who both lift through the summer. The first finishes every workout with suicides and endless defensive slides until his legs are burning. The second keeps his strength work, but at the start of a couple of sessions a week adds a short block of crisp jumps, quick lateral bounds and first-step starts from a stance, with full rest between each. By the first game both are stronger. Only the second blows past his defender off the dribble and gets up for rebounds he used to miss, because only he trained his first step at full speed.',
              },
              batBall: {
                title: 'Two hitters, one off-season',
                body: 'Picture two softball players who both get stronger over the winter. The first spends her extra time grinding through slow, heavy work and long sessions of half-effort swings. The second keeps her strength work and adds short blocks of explosive rotational medicine-ball throws and full-intent swings with plenty of rest, early in her sessions while she is fresh. By spring both are stronger. Only the second has clearly more bat speed, because only she taught her body to turn strength into rotation, quickly, from the ground up.',
              },
              racket: {
                title: 'Two players, one winter',
                body: 'Picture two badminton players who both start strength training in the autumn. The first adds long, exhausting footwork drills at the end of every session, moving around the court until he can barely lift his racket. The second keeps his strength work and, early in a couple of sessions a week, adds sharp split steps, explosive lunges and quick pushes to each corner with full recovery between efforts. By the new year both are stronger. Only the second is clearly earlier to the shuttle, because only he trained speed at speed.',
              },
              endurance: {
                title: 'Two swimmers, one season',
                body: 'Picture two swimmers who both add land-based strength work in the autumn. The first does nothing else differently, and all her sprint work happens at the end of long, tiring sets in the pool. The second keeps her strength work, adds a few explosive jumps on land, and in the pool practises starts and turns at full speed with plenty of rest, early in practice when she is fresh. By the championship both are stronger. Only the second is clearly faster off the blocks and the walls, because only she practised being explosive at race speed.',
              },
              track: {
                title: 'Two sprinters, one winter',
                body: 'Picture two young sprinters who both get stronger over the winter. The first trains hard but runs most of his sprints tired, with short rests, at the end of sessions. The second keeps his strength work, adds sharp bounds and hops, and practises block starts and accelerations at full speed early in sessions, walking back slowly and only going again when ready. By the first outdoor meet both are stronger. Only the second clears the blocks noticeably faster and is ahead at the halfway mark, because only he trained speed at speed.',
              },
              combat: {
                title: 'Two wrestlers, one season',
                body: 'Picture two wrestlers who both start lifting in the off-season. The first finishes every practice with long, exhausting drilling until he is wrecked, all at half pace. The second keeps his strength work and, early in a couple of practices a week, adds short bursts of explosive level changes, penetration steps and jumps, done sharp with rest between them. By the season both are stronger. Only the second hits his shot before his opponent can react, because only he practised his entry at real speed.',
              },
              artistic: {
                title: 'Two gymnasts, one season',
                body: 'Picture two gymnasts who both get stronger with conditioning over the summer. The first does all her jumps and tumbling drills at the end of long sessions, when her legs are tired and her landings sloppy. The second keeps her strength work and adds short, sharp blocks of rebound jumps and fast take-offs early in practice, resting fully between them. By the autumn both are stronger. Only the second has noticeably more height on her tumbling and snap off the vault board, because only she trained her take-off at full speed.',
              },
              precision: {
                title: 'Two golfers, one winter',
                body: 'Picture two golfers who both get stronger over the winter. The first trains in the gym but hits balls only at an easy, comfortable tempo. The second keeps his strength work and adds short sessions of explosive rotational throws and full-intent speed swings, with plenty of rest, while he is fresh, alongside his normal practice. By spring both are stronger. Only the second has clearly more clubhead speed and distance, because only he asked his body to use its new strength quickly, from the ground up.',
              },
              strength: {
                title: 'Two lifters, one cycle',
                body: 'Picture two young weightlifters who both get stronger in their squats and pulls over a training cycle. The first treats every session as a grind and rarely practises moving lighter weights fast. The second keeps her strength work but also spends part of each week on crisp, fast technical lifts and jumps with full intent and plenty of rest, as her coach programmes them. By the next meet both are stronger. Only the second is quicker under the bar and makes her final attempts, because only she trained speed at speed.',
              },
              board: {
                title: 'Two BMX riders, one winter',
                body: 'Picture two BMX racers who both start lifting in the off-season. The first adds long, grinding sessions on the bike until his legs are empty. The second keeps his strength work and adds short, explosive jumps and full-effort gate starts with long rests, early in sessions when he is fresh. By the first race of spring both are stronger. Only the second is clearly first to the opening jump and into the first turn, because only he trained his gate start at full speed.',
              },
            },
          },
        },
      ],
    },
    {
      title: 'What fast looks like',
      blocks: [
        { p: 'Most sports are decided by short, sharp moments, not long ones. Almost nobody needs true top speed for long; what wins is the first few steps, the take-off, the swing or the burst. So it pays to understand what good explosive movement looks like, even if your coach handles the details. A few principles hold almost everywhere.' },
        { p: 'Fast movement starts from the ground and travels up. Your legs push, your hips and trunk pass that force on, and your arms or the implement in your hands are the last link. When the links fire in order, each one adds speed to the next. When one fires early or late — the arms before the hips, the shoulders before the legs — force leaks out and the movement feels busy but slow.' },
        {
          p: 'Direction matters as much as amount. When you accelerate from a standstill, your body leans forward and your feet push back and down behind you, a bit like pushing a heavy car. The lean is not a bend at the waist; it is your whole body tilted from ankle to head, in one line. As you pick up speed you rise gradually, step by step. Push in the direction you want to go, and every bit of strength counts.',
          variants: {
            court: 'Direction matters as much as amount. On a court, the first step is often sideways or at an angle, not straight ahead. A good first step comes from a low, balanced stance, with your push foot driving into the floor in the direction you want to go, rather than a false step backwards to get started. Jumps work the same way: a quick, deep enough dip and a straight push up through the floor. Push in the direction you want to go, and every bit of strength counts.',
            batBall: 'Direction matters as much as amount. In hitting and throwing, the push is into the ground and then rotational: a firm front leg, the hips turning before the shoulders, the hands arriving last. That separation between hips and shoulders stores energy and releases it through the swing. On the bases, the lean-and-push of a sprint start applies. Push in the direction you want the energy to go, and every bit of strength counts.',
            racket: 'Direction matters as much as amount. In racket sports, speed starts with the split step: a small hop timed with your opponent’s contact, so you land loaded and ready to push towards the ball. The best first steps drive off the outside leg in the direction you want to go. Stroke power works from the ground up too, through the legs and trunk before the arm. Push in the direction you want to go, and every bit of strength counts.',
            endurance: 'Direction matters as much as amount. A swimming start is a push from the blocks out and forward into a long, streamlined line; a turn is a quick tuck and a strong push from the wall. A rowing start drives with the legs before the back and arms. A cycling sprint drives down through the pedals while the trunk stays still. In each case, force aimed in the direction of travel goes further. Push where you want to go, and every bit of strength counts.',
            combat: 'Direction matters as much as amount. A good takedown shot starts with a quick level change and a long penetration step that drives forward through your opponent, not down towards the mat. A fencing lunge launches from the back leg with the front foot reaching, the body staying level. A judo entry turns the hips in quickly before the pull. Push in the direction you want to go, and every bit of strength counts.',
            artistic: 'Direction matters as much as amount. In tumbling, vaulting and leaps, the run-up builds speed and the take-off redirects it upwards. A good take-off is short and stiff: the body stays tall and blocks against the floor or board, rather than sinking and absorbing the speed you built. Arms drive up in time with the legs. Push in the direction you want to go, and every bit of strength counts.',
            precision: 'Direction matters as much as amount. In a golf swing, the push goes into the ground, then into rotation: the lower body starts the downswing, the trunk follows and the arms and club arrive last. Players who start with the arms lose speed however strong they are. In archery and shooting, the direction that matters is stillness: force balanced and held, not released. Train for the movement your sport actually asks for.',
            strength: 'Direction matters as much as amount. In the snatch and the clean, the bar stays close and travels up as you drive through the floor, then extend hips, knees and ankles together; then you move yourself under it, fast. A bar that swings out in front is force spent going sideways. In powerlifting, a straight, consistent bar path does the same job. Push where you want the bar to go, and every bit of strength counts.',
            board: 'Direction matters as much as amount. Popping an ollie or a bunny hop is a quick, sharp push down and up, timed with the board or bike, not a slow squat. A BMX gate start or a ski start throws your weight forward over the front as you drive. A surf pop-up is one fast push from the deck. A dynamic climbing move starts from the legs. Push where you want to go, and every bit of strength counts.',
          },
        },
        { p: 'Relaxation matters more than most athletes think. Tension in the face, neck and hands leaks speed: sprinters, hitters, fighters and lifters all talk about staying loose as they get faster. Clenching your jaw doesn’t add power. It only stiffens the parts that should be relaxed, and slows the muscles that need to switch on and off quickly. Fast athletes often look as if they are working less hard than everyone around them.' },
        { h: 'Small fixes, big returns' },
        { p: 'Common habits that cost young athletes speed are easy to spot on video: standing up straight on the first step, reaching a foot far out in front, arms swinging across the body, swinging with the arms before the hips have turned, sinking into a take-off instead of blocking up, or pulling the bar away from the body. These are technique issues, not strength issues. A strong athlete with messy mechanics is pouring force in the wrong direction.' },
        { p: 'Ask a coach to film a few of your explosive moments from the side: starts, first steps, swings, take-offs, entries, lifts. Watch the clip back slowly. Is the movement starting from the ground? Are you pushing in the direction you want to go? Is your face relaxed? One clear cue at a time is plenty. Athletes who chase five fixes at once usually end up moving stiffly and thinking too much.' },
      ],
    },
    {
      title: 'Patience, testing and your plan',
      blocks: [
        { p: 'Speed adapts slowly, and it adapts unevenly. Your nervous system needs weeks of repeated, high-quality exposure before the changes show up on a clock or a measuring tape, and progress often comes in steps rather than a smooth line. It is normal to train well for several weeks and see little, then notice a jump. That is not a sign something is wrong; it is how this quality tends to develop.' },
        { p: 'Fatigue is the enemy of speed work in a way it isn’t for most other training. You can still build some endurance when tired. You cannot build top speed when tired, because you can’t reach top speed. That is why speed work the day after a brutal {event}, or after a short night of sleep, often feels flat. On those days, it is smart to do less and keep the quality, or swap to something else entirely.' },
        { p: 'Keep your strength work going while you build speed. Athletes sometimes swing from one extreme to the other: all lifting for a season, then all speed work. The better approach is to keep both in the week and let your coach shift the emphasis as {events} get closer. Strength you stop training fades slowly; speed you never practise never arrives. Together they support each other.' },
        { h: 'Test it the same way every time' },
        {
          p: 'To know whether you’re actually getting faster, you need a fair test. Pick one measure relevant to your sport — a short sprint, a jump, a throw, a timed start — and keep everything else the same: same surface, same shoes, same type of start, same warm-up, same time of day if you can, and the same timing method. Hand timing with a phone is useful for spotting trends but less precise than timing gates, so compare like with like.',
          variants: {
            court: 'To know whether you’re actually getting faster, you need a fair test. For court athletes, a short sprint or shuttle and a vertical jump against a wall or a jump mat are good choices. Keep everything else the same: same floor, same shoes, same warm-up, same time of day if you can, and the same way of measuring. A phone video is useful for spotting trends but less precise than proper timing or a jump mat, so compare like with like.',
            batBall: 'To know whether you’re actually getting faster, you need a fair test. Bat speed or exit velocity measured with the same device, throwing velocity on the same radar, or home-to-first time on the same field are all good choices. Keep everything else the same: same bat, same warm-up, same time of day if you can. Compare like with like; different sensors and radar guns often read differently.',
            endurance: 'To know whether you’re actually getting faster at the explosive parts of your race, you need a fair test: a timed start to a fixed distance off the blocks, a timed turn, a short all-out rowing or cycling effort from a standing start. Keep everything else the same: same pool or course, same equipment, same warm-up, same time of day if you can, and the same timing method. Compare like with like.',
            precision: 'To know whether anything is changing, you need a fair test. For golfers, clubhead or ball speed on the same launch monitor with the same club is ideal. For archers and shooters, a better test is how steady your groups stay late in a long session. Keep everything else the same: same equipment, same warm-up, same time of day if you can. Compare like with like.',
            strength: 'To know whether you’re actually getting faster, you need a fair test. Some lifters use a vertical jump; others watch bar speed on a phone app or a device, with the same lift and the same setup each time. Keep everything else the same: same warm-up, same time of day if you can, the same method. Your coach can tell you which measure fits your programme. Compare like with like.',
            board: 'To know whether you’re actually getting faster, you need a fair test: a timed gate start to a fixed point, a vertical jump, a timed run of the same short section in similar conditions. Keep everything else the same: same equipment, same warm-up, same time of day if you can, and the same timing method. Snow, wind, waves and track surfaces vary, so write the conditions down and compare like with like.',
          },
        },
        { p: 'Test when you are fresh, not at the end of a heavy week. Take your best of a few attempts with full rest between them. Test every few weeks rather than every few days, since speed doesn’t move fast enough to show change daily, and frequent testing only adds fatigue. Write down the conditions next to the result, so a windy day or a slippery surface doesn’t fool you.' },
        { h: 'Work with your coach and the Workout tab' },
        { p: 'Your coach sees the whole week: practice, {events}, conditioning, how tired you are. The Workout tab in AthleteOS builds sessions around your schedule and sets the actual exercises and volumes. This briefing is about principles, so you understand why your plan looks the way it does and can tell your coach what you’ve noticed. If you’d like more speed emphasis, ask. Coaches generally welcome athletes who understand the reasons behind the work.' },
        { protocol: { title: 'Your week', steps: [
          'Talk to your coach about where speed and power work fits into your week, and put it early in the session, right after a full warm-up, on days when you are fresh.',
          'In every jump, throw, sprint, swing or explosive lift, move with full intent. When the quality drops, stop for the day — that’s the session doing its job, not you falling short.',
          'Take full rest between fast efforts: walk around, breathe, and only go again when you feel genuinely ready to move at your best.',
          'Ask someone to film a few of your explosive moments from the side, and pick one simple cue to focus on, such as “push where you want to go”.',
          'Choose one speed test that fits your sport, write down exactly how you do it, and repeat it the same way every few weeks when you are fresh.',
        ] } },
        { p: 'You’ll know it’s working when your explosive moments feel sharper before the numbers confirm it: you get there first, the movement feels easier, your test results creep in the right direction under the same conditions. If they don’t move after a couple of months of consistent, fresh speed work, that is useful information to bring to your coach. And if fast work brings sharp pain, pain in one spot, swelling or pain that gets worse, stop and get it checked by a doctor or physio before you go fast again.' },
      ],
    },
  ],
  sources: ['youthStrength'],
};
