# TPF Tournament Two-Phase System - Implementation Plan

## 📋 Summary of Requirements

Based on PDF and user responses:

### Tournament Structure
1. **Phase 1**: Groups 1-4 (3 teams each, round-robin)
2. **Phase 2**: Groups A-D (3 teams each: 1 winner from Phase 1 + 1 runner-up from Phase 1 + 1 seeded/fixed team)
3. **Phase 3**: Knockout (Quarter Finals → Semi Finals → Final)

### Key Features
- ✅ Two-phase group system with automatic advancement
- ✅ Seeded/fixed teams in Phase 2
- ✅ Tournament rules acceptance (during registration + dashboard view)
- ✅ Court & time assignment (group-level + match-level)
- ✅ Enhanced scoring: Current system (wins/diff) + placement bonus (1st: +10, 2nd: +7, 3rd: +5)
- ✅ Overall leaderboard across all TPF tournaments (future feature)
- ✅ Match notifications: -30 mins, -10 mins, on-time

---

## 🗂️ Firestore Data Structure

### Tournament Document
```javascript
tournaments/{tournamentId} {
  // Basic Info
  name: "TPF Sheikh Zayed",
  description: "TPF 24-Jan Tournament",
  imageUrl: "assets/images/tpf.png",
  type: "two-phase-knockout", // NEW: "simple", "two-phase-knockout"
  status: "upcoming" | "phase1" | "phase2" | "knockout" | "completed",
  
  // Rules
  rules: {
    text: "All games are Deciding until Semi Final stage...",
    acceptanceRequired: true
  },
  
  // PHASE 1: Initial Groups (1-4)
  phase1: {
    name: "Initial Groups",
    groups: {
      "Group 1": {
        teamKeys: ["teamKey1", "teamKey2", "teamKey3"],
        schedule: {
          court: "Court 1",
          startTime: "7:45 PM",
          endTime: "9:15 PM"
        },
        orderOfPlay: [
          "Team 1 vs Team 2",
          "Team 2 vs Team 3",
          "Team 1 vs Team 3"
        ]
      },
      "Group 2": {...},
      "Group 3": {...},
      "Group 4": {...}
    }
  },
  
  // PHASE 2: Advanced Groups (A-D)
  phase2: {
    name: "Advanced Groups",
    groups: {
      "Group A": {
        teamSlots: [
          { type: "winner", from: "Group 1", teamKey: null }, // Filled after Phase 1
          { type: "runnerUp", from: "Group 4", teamKey: null },
          { type: "seeded", name: "Ziad Rizk / Seif", teamKey: "seeded_1" }
        ],
        schedule: {
          court: "Court 2",
          startTime: "9:20 PM",
          endTime: "10:45 PM"
        }
      },
      "Group B": {
        teamSlots: [
          { type: "winner", from: "Group 2", teamKey: null },
          { type: "runnerUp", from: "Group 3", teamKey: null },
          { type: "seeded", name: "Nabil / Abu", teamKey: "seeded_2" }
        ],
        schedule: {
          court: "Court 3",
          startTime: "9:20 PM",
          endTime: "10:45 PM"
        }
      },
      "Group C": {...},
      "Group D": {...}
    }
  },
  
  // KNOCKOUT BRACKET
  knockout: {
    quarterFinals: [
      {
        id: "qf1",
        team1: { type: "winner", from: "Group A", teamKey: null },
        team2: { type: "runnerUp", from: "Group B", teamKey: null },
        schedule: {
          court: "Court 1",
          startTime: "10:50 PM",
          endTime: "11:45 PM"
        },
        winner: null
      },
      {...}, // qf2, qf3, qf4
    ],
    semiFinals: [
      {
        id: "sf1",
        team1: { type: "winner", from: "qf1", teamKey: null },
        team2: { type: "winner", from: "qf4", teamKey: null },
        schedule: {...},
        winner: null
      },
      {...} // sf2
    ],
    final: {
      id: "final",
      team1: { type: "winner", from: "sf1", teamKey: null },
      team2: { type: "winner", from: "sf2", teamKey: null },
      schedule: {
        court: "Court 1",
        startTime: "12:00 AM",
        endTime: "12:30 AM"
      },
      winner: null
    }
  },
  
  // Timestamp
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Tournament Match Document (Enhanced)
```javascript
tournamentMatches/{matchId} {
  tournamentId: "xxx",
  tournamentName: "TPF Sheikh Zayed",
  phase: "phase1" | "phase2" | "knockout",
  groupName: "Group 1" | "Group A" | "qf1" | "sf1" | "final",
  
  team1Key: "xxx",
  team1Name: "Hussein / Karim",
  team2Key: "yyy",
  team2Name: "Ibrahim / 7ossam",
  
  score: "6-1 6-1",
  winner: "team1" | "team2" | null,
  scoreDifference: 10,
  
  // NEW: Scheduling
  schedule: {
    court: "Court 1",
    startTime: "7:45 PM",
    estimatedEndTime: "8:15 PM",
    actualEndTime: null
  },
  
  // NEW: Notifications
  notificationsSent: {
    thirtyMinBefore: false,
    tenMinBefore: false,
    onTime: false
  },
  
  timestamp: Timestamp,
  completedAt: Timestamp | null
}
```

### Tournament Registration (Enhanced)
```javascript
tournamentRegistrations/{registrationId} {
  // Existing fields...
  tournamentId: "xxx",
  userId: "xxx",
  firstName: "Hussein",
  lastName: "Karim",
  partner: {...},
  status: "approved",
  
  // NEW: Rules acceptance
  rulesAccepted: true,
  rulesAcceptedAt: Timestamp,
  
  // Existing timestamps...
  createdAt: Timestamp
}
```

### Overall Leaderboard Collection (Future)
```javascript
tpfOverallStandings/{userId} {
  userId: "xxx",
  playerName: "Hussein Karim",
  
  // Cumulative stats across ALL TPF tournaments
  totalPoints: 45,
  tournamentsPlayed: 3,
  
  placements: [
    { tournamentId: "xxx", tournamentName: "TPF 24-Jan", placement: 1, points: 10 },
    { tournamentId: "yyy", tournamentName: "TPF 15-Feb", placement: 3, points: 5 }
  ],
  
  wins: 12,
  losses: 3,
  
  updatedAt: Timestamp
}
```

---

## 📱 UI Changes

### 1. Tournament Dashboard Tabs (Update)
Current: **Groups | Standings | Playoffs | Matches**

Enhanced for Two-Phase:
- **Groups** tab → Show Phase 1 and Phase 2 separately
- **Standings** tab → Group by phase, add placement bonus
- **Playoffs** tab → Show knockout bracket
- **Matches** tab → Filter by phase
- **NEW: Rules** tab → View tournament rules

### 2. Groups Tab UI
```
┌─────────────────────────────────────┐
│ 📍 PHASE 1 - Initial Groups        │
│ Status: Completed ✓                │
└─────────────────────────────────────┘
  
  ┌─ Group 1 ─────────────────────┐
  │ Court 1 | 7:45 PM - 9:15 PM   │
  │ 3 teams                        │
  │ [View Standings]               │
  └────────────────────────────────┘
  
┌─────────────────────────────────────┐
│ 📍 PHASE 2 - Advanced Groups       │
│ Status: In Progress 🔄             │
└─────────────────────────────────────┘
  
  ┌─ Group A ─────────────────────┐
  │ Court 2 | 9:20 PM - 10:45 PM  │
  │ • Winner Group 1 (Hussein)    │
  │ • Runner-up Group 4 (...)     │
  │ • Ziad Rizk / Seif (seeded)   │
  └────────────────────────────────┘
```

### 3. Standings Tab UI (Enhanced)
```
┌─────────────────────────────────────┐
│ Group 1 - Phase 1         Top 2 ✓  │
├─────────────────────────────────────┤
│ Pos | Team           | Pts | +/- |W│
│  1  | Hussein/Karim  | 13  | +8  |2│ ← +10 bonus
│  2  | Ibrahim/7ossam |  7  | +2  |1│ ← +7 bonus
│  3  | Hussein/Derwi  |  0  | -10 |0│
└─────────────────────────────────────┘

Scoring:
• Win: +3 pts
• Placement Bonus: 1st: +10, 2nd: +7, 3rd: +5
```

---

## 🔔 Match Notification System

### Cloud Function: `sendMatchReminders`
Scheduled every 5 minutes, checks for upcoming matches.

```javascript
exports.sendMatchReminders = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    const now = new Date();
    
    // Query all scheduled matches
    const matchesSnapshot = await admin.firestore()
      .collection('tournamentMatches')
      .where('schedule.startTime', '!=', null)
      .get();
    
    for (const matchDoc of matchesSnapshot.docs) {
      const match = matchDoc.data();
      const startTime = parseTime(match.schedule.startTime); // Parse "7:45 PM"
      const diffMinutes = getTimeDifference(now, startTime);
      
      // Send 30-min reminder
      if (diffMinutes === 30 && !match.notificationsSent?.thirtyMinBefore) {
        await sendMatchNotification(match, 30);
        await matchDoc.ref.update({ 'notificationsSent.thirtyMinBefore': true });
      }
      
      // Send 10-min reminder
      if (diffMinutes === 10 && !match.notificationsSent?.tenMinBefore) {
        await sendMatchNotification(match, 10);
        await matchDoc.ref.update({ 'notificationsSent.tenMinBefore': true });
      }
      
      // Send on-time notification
      if (diffMinutes === 0 && !match.notificationsSent?.onTime) {
        await sendMatchNotification(match, 0);
        await matchDoc.ref.update({ 'notificationsSent.onTime': true });
      }
    }
  });
```

---

## 🚀 Implementation Steps

### Phase 1: Data Structure & Admin Setup (1-2 days)
- [ ] Update Firestore data model for two-phase tournaments
- [ ] Create admin UI to set up Phase 1 groups with court/time
- [ ] Create admin UI to configure Phase 2 with seeded teams
- [ ] Create admin UI to configure knockout bracket

### Phase 2: Rules System (0.5 days)
- [ ] Add rules field to tournament document
- [ ] Show rules dialog during registration
- [ ] Add "Rules" tab to tournament dashboard
- [ ] Save rules acceptance in registration document

### Phase 3: Group Advancement Logic (1 day)
- [ ] Calculate Phase 1 standings with placement bonus
- [ ] Auto-fill Phase 2 team slots when Phase 1 completes
- [ ] Admin button to "Advance to Phase 2"
- [ ] Show Phase 2 groups with correct teams

### Phase 4: Match Scheduling (1 day)
- [ ] Add court/time fields to match creation
- [ ] Estimate match end times (30 mins per match default)
- [ ] Update UI to show match schedule
- [ ] Admin can manually adjust times

### Phase 5: Knockout Bracket (1 day)
- [ ] Build bracket visualization UI
- [ ] Admin can enter knockout match results
- [ ] Auto-advance winners through bracket
- [ ] Show final winner

### Phase 6: Enhanced Standings (0.5 days)
- [ ] Add placement bonus calculation (+10/+7/+5)
- [ ] Update standings display
- [ ] Show phase-specific standings

### Phase 7: Match Notifications (1 day)
- [ ] Create `sendMatchReminders` Cloud Function
- [ ] Test notification timing
- [ ] Deploy and verify

### Phase 8: Overall Leaderboard (Future - 1-2 days)
- [ ] Create `tpfOverallStandings` collection
- [ ] Update standings after each tournament
- [ ] Create overall leaderboard screen

---

## ⚠️ Important Notes

1. **First Time Setup**: For TPF Sheikh Zayed, admin will manually configure everything. Future tournaments can use this as a template.

2. **Template System (Future)**: Save this tournament config as "TPF Two-Phase Template" for reuse.

3. **Match Time Parsing**: Need to parse times like "7:45 PM" and compare with current time for notifications.

4. **Seeded Teams**: Store as simple strings, not linked to user accounts (they might not be registered users).

5. **Testing**: Test with small data first, then migrate real TPF tournament.

---

## 🎯 Priority Order

**Immediate (This Week)**:
1. Phase 1: Admin setup UI for two-phase structure
2. Phase 2: Rules acceptance
3. Phase 3: Group advancement logic
4. Phase 4: Match scheduling

**Next Week**:
5. Phase 5: Knockout bracket
6. Phase 6: Enhanced standings
7. Phase 7: Match notifications

**Future**:
8. Phase 8: Overall leaderboard
9. Tournament templates

---

**Ready to start implementation!**
