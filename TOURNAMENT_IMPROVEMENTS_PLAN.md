# Tournament System Improvements

## Date: February 7, 2026  
## Status: 🔄 IN PROGRESS

---

## ✅ COMPLETED Changes

### 1. Player Level Options Updated
**File:** `lib/screens/tournament_join_screen.dart`
- Changed from: `['Beginner', 'D', 'C', 'B', 'A']`
- Changed to: `['C+', 'C', 'D', 'Beginner']`

### 2. Match Notifications - Timing Fixed
**File:** `functions/index.js`
- Removed "now" notification (at match time)
- Kept only:  
  - 30 minutes before match
  - 10 minutes before match

### 3. Parent Tournament UI - Hide Groups/Playoffs/Matches
**File:** `lib/screens/tournament_dashboard_screen.dart`
- Parent tournaments now only show 2 tabs: **Standings** and **Rules**
- Normal tournaments show all 5 tabs: **Groups**, **Standings**, **Playoffs**, **Matches**, **Rules**
- Admin actions (Add Groups, Add Match) hidden for parent tournaments
- Uses `isParentTournament` field to determine tab structure

---

## 🚧 REMAINING TODOs

### 4. Add Court Number & Match Time to Groups

**Current Structure:**
```firestore
tournaments/{tournamentId}
  └─ groups: {
       "Group 1": ["teamKey1", "teamKey2"],
       "Group 2": ["teamKey3", "teamKey4"]
     }
```

**Proposed New Structure:**
```firestore
tournaments/{tournamentId}
  └─ groups: {
       "Group 1": {
         teamKeys: ["teamKey1", "teamKey2"],
         schedule: {
           court: "Court 1",
           startTime: "7:45 PM",
           endTime: "9:15 PM"
         }
       },
       "Group 2": {
         teamKeys: ["teamKey3", "teamKey4"],
         schedule: {
           court: "Court 2",
           startTime: "7:45 PM",
           endTime: "9:15 PM"
         }
       }
     }
```

**Impact Analysis:**
This change affects multiple files:
- ✅ `lib/screens/phase1_setup_screen.dart` - Already uses this structure!
- ⚠️ `lib/screens/tournament_groups_screen.dart` - Needs update
- ⚠️ `lib/screens/tournament_dashboard_screen.dart` - Needs update (group standings calculation)
- ⚠️ Any other code reading `groups` field

**Decision Needed:**
- **Option A**: Implement new structure for all tournaments (breaking change, requires data migration)
- **Option B**: Keep current simple structure, add schedule as separate field per group
- **Option C**: Only use Phase 1/Phase 2 system (which already has this) for tournaments needing schedules

### 5. Auto-Grouping Based on Player Registration Level

**Requirement:**
Group players automatically based on their skill level:
- C+ players → Group C+
- C players → Group C
- D players → Group D
- Beginner players → Group Beginner

**Implementation Approach:**
1. When admin clicks "Create Groups"
2. Query all approved registrations
3. Group by `level` field
4. Create groups named after levels (instead of "Group 1", "Group 2")
5. Assign teams to groups based on their level

**Files to Modify:**
- `lib/screens/tournament_groups_screen.dart` - `_createGroups()` method
- Add new `_createGroupsByLevel()` method

**Questions:**
- What if a level has too many/too few teams?
- Should there be a minimum/maximum teams per group?
- What about mixed-level pairs (if partners have different levels)?

---

## 📝 Notes & Decisions

### Parent Tournament Behavior
✅ **Confirmed:**
- Parent tournaments are for overall standings only
- They aggregate results from sub-tournaments (weekly tournaments)
- No groups, playoffs, or matches at parent level
- Only display cumulative standings

### Match Notification Timing
✅ **Confirmed:**
- Send at 30 minutes before
- Send at 10 minutes before
- Do NOT send at match start time

### Player Level Order
✅ **Confirmed:**
- Display order: C+, C, D, Beginner (highest to lowest)

---

## 🎯 Recommendations

### For Court/Time Schedule:
I recommend **Option B** for now:
- Keep groups as simple lists for backwards compatibility
- Add optional `groupSchedules` field:
  ```
  groupSchedules: {
    "Group 1": { court: "Court 1", startTime: "7:45 PM", endTime: "9:15 PM" },
    "Group 2": { court: "Court 2", startTime: "7:45 PM", endTime: "9:15 PM" }
  }
  ```
- Phase 1/Phase 2 tournaments already have proper structure
- Simpler tournaments can add schedules optionally

### For Auto-Grouping:
- Implement as separate button: "Auto-Group by Level"
- Keep manual grouping option
- Show preview before applying
- Handle edge cases (mixed levels, uneven distribution)

---

## ⏭️ Next Steps

Please confirm:
1. ✅ Approach for court/time schedule (Option A/B/C)?
2. ✅ Auto-grouping logic and edge case handling?
3. Any other tournament features or changes needed?

Once confirmed, I'll implement the remaining features.
