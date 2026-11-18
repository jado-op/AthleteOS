-- DropForeignKey
ALTER TABLE "AthleteSport" DROP CONSTRAINT "AthleteSport_athleteId_fkey";

-- DropForeignKey
ALTER TABLE "Competition" DROP CONSTRAINT "Competition_athleteId_fkey";

-- DropForeignKey
ALTER TABLE "Plan" DROP CONSTRAINT "Plan_athleteId_fkey";

-- DropForeignKey
ALTER TABLE "PlannedSession" DROP CONSTRAINT "PlannedSession_planId_fkey";

-- DropForeignKey
ALTER TABLE "PlannedItem" DROP CONSTRAINT "PlannedItem_plannedSessionId_fkey";

-- DropForeignKey
ALTER TABLE "Session" DROP CONSTRAINT "Session_plannedSessionId_fkey";

-- DropForeignKey
ALTER TABLE "SkillBlock" DROP CONSTRAINT "SkillBlock_athleteId_fkey";

-- DropForeignKey
ALTER TABLE "CoachReport" DROP CONSTRAINT "CoachReport_athleteId_fkey";

-- DropForeignKey
ALTER TABLE "LeagueMember" DROP CONSTRAINT "LeagueMember_leagueId_fkey";

-- DropForeignKey
ALTER TABLE "LeagueMember" DROP CONSTRAINT "LeagueMember_athleteId_fkey";

-- DropForeignKey
ALTER TABLE "WeeklyXP" DROP CONSTRAINT "WeeklyXP_athleteId_fkey";

-- AlterTable
ALTER TABLE "Session" DROP COLUMN "plannedSessionId";

-- DropTable
DROP TABLE "AthleteSport";

-- DropTable
DROP TABLE "Competition";

-- DropTable
DROP TABLE "Plan";

-- DropTable
DROP TABLE "PlannedSession";

-- DropTable
DROP TABLE "PlannedItem";

-- DropTable
DROP TABLE "SkillBlock";

-- DropTable
DROP TABLE "CoachReport";

-- DropTable
DROP TABLE "League";

-- DropTable
DROP TABLE "LeagueMember";

-- DropTable
DROP TABLE "WeeklyXP";

-- DropEnum
DROP TYPE "CompetitionKind";

