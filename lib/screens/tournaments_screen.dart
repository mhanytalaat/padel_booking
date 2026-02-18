import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_join_screen.dart';
import 'tournament_dashboard_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class TournamentsScreen extends StatefulWidget {
  const TournamentsScreen({super.key});

  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  int _selectedTab = 0; // 0 = Available Tournaments, 1 = My Tournaments

  void _showWeeklyTournamentsDialog(BuildContext context, String parentTournamentId, String parentName) async {
    try {
      // Get all weekly tournaments for this parent
      final weeklyTournamentsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('parentTournamentId', isEqualTo: parentTournamentId)
          .get();

      if (!context.mounted) return;

      // Sort client-side by date
      final weeklyTournaments = weeklyTournamentsSnapshot.docs;
      weeklyTournaments.sort((a, b) {
        final aDate = (a.data())['date'] as String? ?? '';
        final bDate = (b.data())['date'] as String? ?? '';
        return aDate.compareTo(bDate);
      });

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$parentName - Weekly Tournaments'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: weeklyTournaments.isEmpty
                ? const Center(
                    child: Text('No weekly tournaments yet.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: weeklyTournaments.length,
                    itemBuilder: (context, index) {
                      final doc = weeklyTournaments[index];
                      final data = doc.data();
                      final name = data['name'] as String? ?? 'Week ${index + 1}';
                      final date = data['date'] as String? ?? '';
                      final status = data['status'] as String? ?? 'upcoming';
                      final tournamentNumber = data['tournamentNumber'] as int?;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                date.isNotEmpty ? date : name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            if (tournamentNumber != null) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#$tournamentNumber',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              status == 'completed' ? Icons.check_circle : Icons.pending,
                              size: 12,
                              color: status == 'completed' ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(status.toUpperCase(), style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!['phase1', 'phase2', 'knockout', 'completed'].contains(status))
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TournamentJoinScreen(
                                        tournamentId: doc.id,
                                        tournamentName: name,
                                        tournamentImageUrl: data['imageUrl'] as String?,
                                      ),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  minimumSize: const Size(55, 32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.login, size: 18),
                                    SizedBox(width: 6),
                                    Text('Join', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TournamentDashboardScreen(
                                      tournamentId: doc.id,
                                      tournamentName: name,
                                    ),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                minimumSize: const Size(70, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.leaderboard, size: 18),
                                  SizedBox(width: 6),
                                  Text('Results', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TournamentDashboardScreen(
                      tournamentId: parentTournamentId,
                      tournamentName: parentName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.emoji_events),
              label: const Text('Overall Standings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading weekly tournaments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to build asset image with proper path handling
  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(
        width: width ?? 60,
        height: height ?? 60,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.emoji_events,
          color: Color(0xFF1E3A8A),
          size: 32,
        ),
      );
    }

    // Normalize the path - ensure it starts with 'assets/'
    String normalizedPath = imagePath.trim();
    
    // Remove leading slash if present
    if (normalizedPath.startsWith('/')) {
      normalizedPath = normalizedPath.substring(1);
    }
    
    // Ensure it starts with 'assets/'
    if (!normalizedPath.startsWith('assets/')) {
      // If it starts with 'images/', add 'assets/' prefix
      if (normalizedPath.startsWith('images/')) {
        normalizedPath = 'assets/$normalizedPath';
      } else {
        // Otherwise, assume it's in assets/images/
        normalizedPath = 'assets/images/$normalizedPath';
      }
    }
    
    return Image.asset(
      normalizedPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Failed to load asset image: $normalizedPath');
        debugPrint('Original path: $imagePath');
        debugPrint('Error: $error');
        return Container(
          width: width ?? 60,
          height: height ?? 60,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.emoji_events,
            color: Color(0xFF1E3A8A),
            size: 32,
          ),
        );
      },
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: const AppHeader(title: 'Tournaments'),
      bottomNavigationBar: const AppFooter(selectedIndex: 2),
      body: Column(
        key: const ValueKey('tournaments_main_column'),
        children: [
          // Tab buttons
          Container(
            color: const Color(0xFF1E3A8A),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _selectedTab = 0);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 0 
                          ? Colors.white 
                          : const Color(0xFF1E3A8A),
                      foregroundColor: _selectedTab == 0 
                          ? const Color(0xFF1E3A8A) 
                          : Colors.white,
                      elevation: _selectedTab == 0 ? 4 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: _selectedTab == 0 
                            ? BorderSide.none 
                            : const BorderSide(color: Colors.white54),
                      ),
                    ),
                    child: const Text(
                      'Available',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _selectedTab = 1);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 1 
                          ? Colors.white 
                          : const Color(0xFF1E3A8A),
                      foregroundColor: _selectedTab == 1 
                          ? const Color(0xFF1E3A8A) 
                          : Colors.white,
                      elevation: _selectedTab == 1 ? 4 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: _selectedTab == 1 
                            ? BorderSide.none 
                            : const BorderSide(color: Colors.white54),
                      ),
                    ),
                    child: const Text(
                      'My Tournaments',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content based on selected tab
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildAvailableTournaments(),
                _buildMyTournaments(user),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableTournaments() {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tour, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No tournaments available',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check back later for upcoming tournaments',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Filter out archived tournaments (isArchived == true) and sort by date
          final tournaments = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isArchived = data['isArchived'] as bool? ?? false;
            return !isArchived;
          }).toList();
          
          // Sort by date (if available), then by name
          tournaments.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aDate = aData['date'] as String? ?? '';
            final bDate = bData['date'] as String? ?? '';
            
            if (aDate.isNotEmpty && bDate.isNotEmpty) {
              return aDate.compareTo(bDate);
            } else if (aDate.isNotEmpty) {
              return -1; // Dates first
            } else if (bDate.isNotEmpty) {
              return 1;
            }
            // If no dates, sort by name
            final aName = aData['name'] as String? ?? '';
            final bName = bData['name'] as String? ?? '';
            return aName.compareTo(bName);
          });

          if (tournaments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tour, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No active tournaments available',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check back later for upcoming tournaments',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Pre-filter visible tournaments for correct gradient indexing
          final visibleTournaments = tournaments.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final parentTournamentId = data['parentTournamentId'] as String?;
            final isHidden = data['hidden'] as bool? ?? false;
            return parentTournamentId == null && !isHidden;
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visibleTournaments.length,
            itemBuilder: (context, index) {
              final doc = visibleTournaments[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] as String? ?? 'Unknown Tournament';
              final description = data['description'] as String? ?? '';
              final imageUrl = data['imageUrl'] as String?;
              final date = data['date'] as String?;
              final tournamentNumber = data['tournamentNumber'] as int?;
              final isParentTournament = data['isParentTournament'] as bool? ?? false;
              final parentTournamentId = data['parentTournamentId'] as String?;
              final skillLevelData = data['skillLevel'];
              final List<String> skillLevels = skillLevelData is List
                  ? (skillLevelData as List).map((e) => e.toString()).toList()
                  : (skillLevelData != null ? [skillLevelData.toString()] : []);

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: index % 2 == 0
                        ? [const Color(0xFF0E7490), const Color(0xFF0F766E)]
                        : [const Color(0xFF059669), const Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    // If parent tournament, show weekly tournaments list
                    if (isParentTournament) {
                      _showWeeklyTournamentsDialog(context, doc.id, name);
                    } else {
                      // Regular tournament - check if started (phase1 or later)
                      final tournamentStatus = data['status'] as String? ?? 'upcoming';
                      final hasStarted = ['phase1', 'phase2', 'knockout', 'completed'].contains(tournamentStatus);
                      if (hasStarted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TournamentDashboardScreen(
                              tournamentId: doc.id,
                              tournamentName: name,
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TournamentJoinScreen(
                              tournamentId: doc.id,
                              tournamentName: name,
                              tournamentImageUrl: imageUrl,
                            ),
                          ),
                        );
                      }
                    }
                  },
                  onLongPress: () {
                    // Long press to open dashboard
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TournamentDashboardScreen(
                          tournamentId: doc.id,
                          tournamentName: name,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imageUrl.startsWith('http')
                                    ? Image.network(
                                        imageUrl,
                                        width: 100,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 60,
                                            height: 60,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.emoji_events,
                                              color: Color(0xFF1E3A8A),
                                              size: 32,
                                            ),
                                          );
                                        },
                                      )
                                    : _buildAssetImage(imageUrl, width: 100, height: 60),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.emoji_events,
                                  color: Color(0xFF1E3A8A),
                                  size: 32,
                                ),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      if (tournamentNumber != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '#$tournamentNumber',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E3A8A),
                                            ),
                                          ),
                                        ),
                                      if (skillLevels.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: skillLevels.map((level) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              level.toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1E3A8A),
                                              ),
                                            ),
                                          )).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (date != null && date.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          date,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Color(0xFF1E3A8A),
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (context) {
                            final hasStarted = ['phase1', 'phase2', 'knockout', 'completed'].contains(data['status'] as String? ?? 'upcoming');
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Upcoming: Join only. Started: Dashboard only. Parent: View Weekly only.
                                    if (isParentTournament || !hasStarted)
                                      Expanded(
                                        child: Container(
                                          height: 44,
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E3A8A),
                                            borderRadius: BorderRadius.circular(22),
                                          ),
                                          child: Text(
                                            isParentTournament
                                                ? 'View Weekly Tournaments'
                                                : 'Join Tournament',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (!isParentTournament && hasStarted)
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => TournamentDashboardScreen(
                                                  tournamentId: doc.id,
                                                  tournamentName: name,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            height: 44,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.green[600],
                                              borderRadius: BorderRadius.circular(22),
                                            ),
                                            child: const Icon(
                                              Icons.leaderboard,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isParentTournament
                                      ? 'Tap for weekly list'
                                      : hasStarted
                                          ? 'Tap 📊 for results'
                                          : 'Tap to join',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.7),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
  }

  Widget _buildMyTournaments(User? user) {
    if (user == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Please log in to view your tournaments',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with trophy icon and text
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          color: const Color(0xFF1E3A8A),
          child: Column(
            children: [
              Icon(
                Icons.emoji_events,
                size: 80,
                color: Colors.amber[300],
              ),
              const SizedBox(height: 16),
              const Text(
                'My tournaments',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        // Tournaments list
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournamentRegistrations')
                .where('userId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.tour,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No tournament registrations',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Join tournaments to see them here',
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                    ],
                  ),
                );
              }

              final registrations = snapshot.data!.docs;
              
              // Sort by timestamp client-side (descending - newest first)
              registrations.sort((a, b) {
                final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                if (aTimestamp == null && bTimestamp == null) return 0;
                if (aTimestamp == null) return 1;
                if (bTimestamp == null) return -1;
                return bTimestamp.compareTo(aTimestamp); // Descending
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: registrations.length,
                itemBuilder: (context, index) {
                  final doc = registrations[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final tournamentName = data['tournamentName'] as String? ?? 'Unknown Tournament';
                  final level = data['level'] as String? ?? 'Unknown';
                  final status = data['status'] as String? ?? 'pending';
                  final timestamp = data['timestamp'] as Timestamp?;
                  final partner = data['partner'] as Map<String, dynamic>?;

                  Color statusColor;
                  String statusText;
                  Color statusBgColor;

                  switch (status) {
                    case 'approved':
                      statusColor = Colors.green[800]!;
                      statusText = 'Approved';
                      statusBgColor = Colors.green[100]!;
                      break;
                    case 'rejected':
                      statusColor = Colors.red[800]!;
                      statusText = 'Rejected';
                      statusBgColor = Colors.red[100]!;
                      break;
                    default:
                      statusColor = Colors.orange[800]!;
                      statusText = 'Pending';
                      statusBgColor = Colors.orange[100]!;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tournamentName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Level: $level',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1E3A8A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (partner != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person, size: 20, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Partner:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          partner['partnerName'] as String? ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          partner['partnerPhone'] as String? ?? 'No phone',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (timestamp != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Registered: ${_formatTimestamp(timestamp)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
