-- CreateTable
CREATE TABLE "SuuntoLink" (
    "athleteId" TEXT NOT NULL,
    "suuntoUser" TEXT NOT NULL,
    "accessToken" TEXT NOT NULL,
    "refreshToken" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SuuntoLink_pkey" PRIMARY KEY ("athleteId")
);

-- CreateIndex
CREATE INDEX "SuuntoLink_suuntoUser_idx" ON "SuuntoLink"("suuntoUser");

-- AddForeignKey
ALTER TABLE "SuuntoLink" ADD CONSTRAINT "SuuntoLink_athleteId_fkey" FOREIGN KEY ("athleteId") REFERENCES "Athlete"("id") ON DELETE CASCADE ON UPDATE CASCADE;
