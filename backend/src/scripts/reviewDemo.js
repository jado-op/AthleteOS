/**
 * App Review demo content, so a reviewer can try teams and shared workouts
 * without a second account: a demo coach with a team and a shared workout. Idempotent; prints the codes.
 *
 *   docker exec student-athlete-api-1 node src/scripts/reviewDemo.js
 */
import { uniqueCode } from '../lib/codes.js';
import { disconnectPrisma, prisma } from '../lib/prisma.js';

const COACH = 'app-review-demo-coach';

const coach = await prisma.athlete.upsert({
  where: { appleUserId: COACH },
  update: {},
  create: { appleUserId: COACH, birthDate: new Date('1985-01-01'), displayName: 'Coach Demo' },
});

let team = await prisma.team.findFirst({ where: { coachId: coach.id, name: 'App Review Demo Team' } });
team ??= await prisma.team.create({ data: { name: 'App Review Demo Team', code: await uniqueCode(prisma), coachId: coach.id } });

let workout = await prisma.sharedWorkout.findFirst({ where: { ownerId: coach.id, title: 'Review demo: leg day' } });
workout ??= await prisma.sharedWorkout.create({
  data: {
    code: await uniqueCode(prisma), ownerId: coach.id, title: 'Review demo: leg day', sportSlug: 'soccer',
    items: [
      { itemSlug: 'goblet-squat', dose: { kind: 'reps', sets: 3, reps: 8 }, restSec: 90 },
      { itemSlug: 'split-squat', dose: { kind: 'reps', sets: 3, reps: 8, perSide: true }, restSec: 60 },
      { itemSlug: 'nordic-hamstring-curl', dose: { kind: 'reps', sets: 3, reps: 5 }, restSec: 90 },
      { itemSlug: 'copenhagen-plank', dose: { kind: 'time', sets: 2, seconds: 20, perSide: true }, restSec: 45 },
      { itemSlug: 'dead-bug', dose: { kind: 'reps', sets: 3, reps: 10 }, restSec: 45 },
    ],
  },
});

console.log(`team    ${team.code}  (${team.name})`);
console.log(`workout ${workout.code}  (${workout.title})`);
await disconnectPrisma();
