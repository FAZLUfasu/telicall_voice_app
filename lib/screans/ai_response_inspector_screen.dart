import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';


class AiResponseInspectorScreen extends StatefulWidget {
  const AiResponseInspectorScreen({super.key});

  @override
  State<AiResponseInspectorScreen> createState() =>
      _AiResponseInspectorScreenState();
}


class _AiResponseInspectorScreenState
    extends State<AiResponseInspectorScreen> {

  // ============================================================
  // NATIVE TELECOM CHANNEL
  // ============================================================

  static const MethodChannel _telecomChannel =
      MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );


  // ============================================================
  // AUDIO PLAYER
  // ============================================================

  final AudioPlayer _audioPlayer =
      AudioPlayer();


  // ============================================================
  // AI RESPONSE FILE LIST
  // ============================================================

  List<String> _aiResponsePaths = [];


  String? _currentlyPlayingPath;


  bool _isPlaying =
      false;


  bool _isLoading =
      false;


  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {

    super.initState();


    // Load already saved AI responses.
    _loadAiResponseFiles();


    // ==========================================================
    // LISTEN FOR NEW AI RESPONSE FILE
    // ==========================================================

    // _telecomChannel.setMethodCallHandler(
    //   (call) async {

    //     // --------------------------------------------------------
    //     // NEW AI RESPONSE SAVED BY CallAiResponseRecorder.kt
    //     // --------------------------------------------------------

    //     if (
    //       call.method ==
    //           'onAiResponseAudioCreated'
    //     ) {

    //       final args =
    //           call.arguments;


    //       String? newPath;


    //       // ======================================================
    //       // EXPECTING MAP FROM KOTLIN
    //       //
    //       // mapOf(
    //       //   "filePath" to filePath,
    //       //   "responseNumber" to responseNumber,
    //       //   "durationMs" to durationMs,
    //       //   "audioBytes" to audioBytes
    //       // )
    //       // ======================================================

    //       if (
    //         args is Map
    //       ) {

    //         newPath =
    //             args['filePath']
    //                 ?.toString();
    //       } else {

    //         // Fallback if only filePath is sent.
    //         newPath =
    //             args?.toString();
    //       }


    //       if (
    //         newPath == null ||
    //         newPath.isEmpty
    //       ) {

    //         return;
    //       }


    //       if (
    //         !mounted
    //       ) {

    //         return;
    //       }


    //       setState(() {

    //         if (
    //           !_aiResponsePaths
    //               .contains(
    //                 newPath,
    //               )
    //         ) {

    //           // Newest AI response first.
    //           _aiResponsePaths.insert(
    //             0,
    //             newPath!,
    //           );
    //         }
    //       });


    //       debugPrint(
    //         '🤖 New AI response received: $newPath',
    //       );
    //     }
    //   },
    // );


    // ==========================================================
    // AUDIO PLAYER STATE
    // ==========================================================

    _audioPlayer
        .onPlayerStateChanged
        .listen(
      (state) {

        if (
          !mounted
        ) {

          return;
        }


        setState(() {

          _isPlaying =
              state ==
                  PlayerState.playing;
        });
      },
    );


    // ==========================================================
    // WHEN AUDIO COMPLETES
    // ==========================================================

    _audioPlayer
        .onPlayerComplete
        .listen(
      (_) {

        if (
          !mounted
        ) {

          return;
        }


        setState(() {

          _isPlaying =
              false;

          _currentlyPlayingPath =
              null;
        });
      },
    );
  }


  // ============================================================
  // LOAD SAVED AI RESPONSE FILES
  // ============================================================

  Future<void> _loadAiResponseFiles() async {

    if (
      _isLoading
    ) {

      return;
    }


    setState(() {

      _isLoading =
          true;
    });


    try {

      final List<dynamic> result =
          await _telecomChannel
              .invokeMethod(
        'getAiResponseRecordings',
      );


      final paths =
          result
              .map(
                (e) =>
                    e.toString(),
              )
              .toList();


      // Newest files first.
      paths.sort(
        (a, b) =>
            b.compareTo(a),
      );


      if (
        !mounted
      ) {

        return;
      }


      setState(() {

        _aiResponsePaths =
            paths;
      });


      debugPrint(
        '🤖 Loaded ${paths.length} AI response recordings',
      );


    } catch (
      e
    ) {

      debugPrint(
        '❌ Error loading AI responses: $e',
      );


      _showMessage(
        'Unable to load AI response recordings',
      );


    } finally {

      if (
        mounted
      ) {

        setState(() {

          _isLoading =
              false;
        });
      }
    }
  }


  // ============================================================
  // PLAY AI RESPONSE
  // ============================================================

  Future<void> _playAiResponse(
    String path,
  ) async {

    try {

      final file =
          File(
        path,
      );


      if (
        !await file.exists()
      ) {

        _showMessage(
          'AI response file does not exist',
        );

        return;
      }


      // ==========================================================
      // SAME FILE IS CURRENTLY PLAYING
      // ==========================================================

      if (
        _currentlyPlayingPath ==
                path &&
            _isPlaying
      ) {

        await _audioPlayer
            .pause();

        return;
      }


      // ==========================================================
      // SAME FILE IS PAUSED
      // ==========================================================

      if (
        _currentlyPlayingPath ==
                path &&
            !_isPlaying
      ) {

        await _audioPlayer
            .resume();

        return;
      }


      // ==========================================================
      // NEW FILE
      // ==========================================================

      await _audioPlayer
          .stop();


      await _audioPlayer
          .play(
        DeviceFileSource(
          path,
        ),
      );


      if (
        !mounted
      ) {

        return;
      }


      setState(() {

        _currentlyPlayingPath =
            path;

        _isPlaying =
            true;
      });


    } catch (
      e
    ) {

      debugPrint(
        '❌ Error playing AI response: $e',
      );


      _showMessage(
        'Unable to play AI response',
      );
    }
  }


  // ============================================================
  // SHARE AI RESPONSE
  // ============================================================

  Future<void> _shareAiResponse(
    String path,
  ) async {

    try {

      final file =
          File(
        path,
      );


      if (
        !await file.exists()
      ) {

        _showMessage(
          'AI response file not found',
        );

        return;
      }


      await _telecomChannel
          .invokeMethod(
        'shareAiResponseRecording',
        {
          'filePath':
              path,
        },
      );


    } catch (
      e
    ) {

      debugPrint(
        '❌ Error sharing AI response: $e',
      );


      _showMessage(
        'Unable to open share menu',
      );
    }
  }


  // ============================================================
  // DELETE ONE AI RESPONSE
  // ============================================================

  Future<void> _deleteAiResponse(
    String path,
  ) async {

    try {

      // Stop if deleting current playing audio.
      if (
        _currentlyPlayingPath ==
            path
      ) {

        await _audioPlayer
            .stop();
      }


      final bool? deleted =
          await _telecomChannel
              .invokeMethod<bool>(
        'deleteAiResponseRecording',
        {
          'filePath':
              path,
        },
      );


      if (
        deleted !=
            true
      ) {

        _showMessage(
          'Unable to delete AI response',
        );

        return;
      }


      if (
        !mounted
      ) {

        return;
      }


      setState(() {

        _aiResponsePaths
            .remove(
          path,
        );


        if (
          _currentlyPlayingPath ==
              path
        ) {

          _currentlyPlayingPath =
              null;

          _isPlaying =
              false;
        }
      });


      _showMessage(
        'AI response deleted',
      );


    } catch (
      e
    ) {

      debugPrint(
        '❌ Error deleting AI response: $e',
      );


      _showMessage(
        'Unable to delete AI response',
      );
    }
  }


  // ============================================================
  // CLEAR ALL AI RESPONSE AUDIO
  // ============================================================

  Future<void> _clearAiResponses() async {

    try {

      await _audioPlayer
          .stop();


      await _telecomChannel
          .invokeMethod(
        'clearAiResponseRecordings',
      );


      if (
        !mounted
      ) {

        return;
      }


      setState(() {

        _aiResponsePaths
            .clear();


        _currentlyPlayingPath =
            null;


        _isPlaying =
            false;
      });


      _showMessage(
        'All AI response recordings cleared',
      );


    } catch (
      e
    ) {

      debugPrint(
        '❌ Error clearing AI responses: $e',
      );


      _showMessage(
        'Unable to clear AI response recordings',
      );
    }
  }


  // ============================================================
  // CONFIRM CLEAR ALL
  // ============================================================

  Future<void> _confirmClearAll() async {

    if (
      _aiResponsePaths
          .isEmpty
    ) {

      return;
    }


    final result =
        await showDialog<bool>(
      context:
          context,

      builder:
          (context) {

        return AlertDialog(

          title:
              const Text(
            'Clear AI Responses?',
          ),

          content:
              const Text(
            'This will permanently delete all saved AI response audio files.',
          ),

          actions: [

            TextButton(
              onPressed:
                  () {

                Navigator.pop(
                  context,
                  false,
                );
              },

              child:
                  const Text(
                'Cancel',
              ),
            ),

            TextButton(
              onPressed:
                  () {

                Navigator.pop(
                  context,
                  true,
                );
              },

              child:
                  const Text(
                'Delete All',
                style:
                    TextStyle(
                  color:
                      Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );


    if (
      result ==
          true
    ) {

      await _clearAiResponses();
    }
  }


  // ============================================================
  // FILE SIZE
  // ============================================================

  Future<String> _getFileSize(
    String path,
  ) async {

    try {

      final file =
          File(
        path,
      );


      if (
        !await file.exists()
      ) {

        return 'File missing';
      }


      final bytes =
          await file
              .length();


      if (
        bytes <
            1024
      ) {

        return '$bytes B';
      }


      if (
        bytes <
            1024 *
                1024
      ) {

        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      }


      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';


    } catch (
      _
    ) {

      return '';
    }
  }


  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
  ) {

    if (
      !mounted
    ) {

      return;
    }


    ScaffoldMessenger
        .of(
          context,
        )
        .showSnackBar(
      SnackBar(
        content:
            Text(
          message,
        ),
      ),
    );
  }


  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {

    return Scaffold(

      backgroundColor:
          const Color(
        0xFFF6F8FC,
      ),


      // ==========================================================
      // APP BAR
      // ==========================================================

      appBar:
          AppBar(

        title:
            const Text(
          'AI Response Audio',
          style:
              TextStyle(
            fontWeight:
                FontWeight.w700,
          ),
        ),


        backgroundColor:
            const Color(
          0xFF102A43,
        ),


        foregroundColor:
            Colors.white,


        actions: [

          // ======================================================
          // DELETE ALL
          // ======================================================

          IconButton(

            icon:
                const Icon(
              Icons.delete_forever,
            ),

            onPressed:
                _aiResponsePaths
                        .isEmpty
                    ? null
                    : _confirmClearAll,

            tooltip:
                'Clear All AI Responses',
          ),


          // ======================================================
          // REFRESH
          // ======================================================

          IconButton(

            icon:
                const Icon(
              Icons.refresh,
            ),

            onPressed:
                _loadAiResponseFiles,

            tooltip:
                'Refresh',
          ),
        ],
      ),


      // ==========================================================
      // BODY
      // ==========================================================

      body:
          _isLoading &&
                  _aiResponsePaths
                      .isEmpty

              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )

              : _aiResponsePaths
                      .isEmpty

                  ? _buildEmptyState()

                  : RefreshIndicator(

                      onRefresh:
                          _loadAiResponseFiles,

                      child:
                          ListView.builder(

                        padding:
                            const EdgeInsets.symmetric(
                          vertical:
                              10,
                        ),

                        itemCount:
                            _aiResponsePaths
                                .length,

                        itemBuilder:
                            (
                          context,
                          index,
                        ) {

                          return _buildAudioCard(
                            _aiResponsePaths[index],
                            index,
                          );
                        },
                      ),
                    ),
    );
  }


  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {

    return Center(

      child:
          Padding(

        padding:
            const EdgeInsets.all(
          30,
        ),

        child:
            Column(

          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            // ====================================================
            // AI ICON
            // ====================================================

            Container(

              width:
                  86,

              height:
                  86,

              decoration:
                  BoxDecoration(

                color:
                    Colors.blue
                        .shade50,

                shape:
                    BoxShape.circle,
              ),

              child:
                  Icon(
                Icons.smart_toy_outlined,
                size:
                    45,
                color:
                    Colors.blue
                        .shade700,
              ),
            ),


            const SizedBox(
              height:
                  20,
            ),


            const Text(
              'No AI Response Audio',
              style:
                  TextStyle(
                fontSize:
                    20,
                fontWeight:
                    FontWeight.w700,
              ),
            ),


            const SizedBox(
              height:
                  10,
            ),


            const Text(
              'AI audio responses sent to the customer will appear here.',
              textAlign:
                  TextAlign.center,
              style:
                  TextStyle(
                fontSize:
                    14,
                color:
                    Colors.grey,
                height:
                    1.5,
              ),
            ),


            const SizedBox(
              height:
                  20,
            ),


            OutlinedButton.icon(

              onPressed:
                  _loadAiResponseFiles,

              icon:
                  const Icon(
                Icons.refresh,
              ),

              label:
                  const Text(
                'Refresh',
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ============================================================
  // AUDIO CARD
  // ============================================================

  Widget _buildAudioCard(
    String filePath,
    int index,
  ) {

    final fileName =
        filePath
            .split(
              Platform.pathSeparator,
            )
            .last;


    final isSelected =
        _currentlyPlayingPath ==
            filePath;


    final responseNumber =
        _aiResponsePaths.length -
            index;


    return Card(

      margin:
          const EdgeInsets.symmetric(
        horizontal:
            12,
        vertical:
            6,
      ),

      elevation:
          1,

      color:
          isSelected
              ? Colors.blue
                  .shade50
              : Colors.white,

      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),


      child:
          Padding(

        padding:
            const EdgeInsets.all(
          4,
        ),

        child:
            ListTile(

          contentPadding:
              const EdgeInsets.symmetric(
            horizontal:
                12,
            vertical:
                6,
          ),


          // ======================================================
          // AI ICON
          // ======================================================

          leading:
              CircleAvatar(

            radius:
                24,

            backgroundColor:
                isSelected
                    ? Colors.blue
                        .shade700
                    : Colors.blue
                        .shade100,

            child:
                Icon(

              isSelected &&
                      _isPlaying

                  ? Icons
                      .pause

                  : Icons
                      .smart_toy_outlined,

              color:
                  isSelected
                      ? Colors.white
                      : Colors.blue
                          .shade800,
            ),
          ),


          // ======================================================
          // TITLE + FILE INFO
          // ======================================================

          title:
              Text(

            'AI Response #$responseNumber',

            style:
                const TextStyle(

              fontWeight:
                  FontWeight.w700,

              fontSize:
                  15,

              color:
                  Color(
                0xFF102A43,
              ),
            ),
          ),


          subtitle:
              Column(

            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              const SizedBox(
                height:
                    5,
              ),


              Text(

                fileName,

                style:
                    const TextStyle(

                  fontSize:
                      12,

                  fontWeight:
                      FontWeight.w500,

                  color:
                      Colors.black54,
                ),
              ),


              const SizedBox(
                height:
                    3,
              ),


              FutureBuilder<String>(

                future:
                    _getFileSize(
                  filePath,
                ),

                builder:
                    (
                  context,
                  snapshot,
                ) {

                  return Text(

                    snapshot.data ??
                        '',

                    style:
                        const TextStyle(
                      fontSize:
                          11,
                      color:
                          Colors.grey,
                    ),
                  );
                },
              ),
            ],
          ),


          // ======================================================
          // ACTIONS
          // ======================================================

          trailing:
              Row(

            mainAxisSize:
                MainAxisSize.min,

            children: [

              // ==================================================
              // PLAY / PAUSE
              // ==================================================

              IconButton(

                padding:
                    EdgeInsets.zero,

                constraints:
                    const BoxConstraints(),

                icon:
                    Icon(

                  isSelected &&
                          _isPlaying

                      ? Icons
                          .pause_circle_filled

                      : Icons
                          .play_circle_fill,

                  color:
                      const Color(
                    0xFF1677FF,
                  ),

                  size:
                      34,
                ),

                tooltip:
                    isSelected &&
                            _isPlaying
                        ? 'Pause'
                        : 'Play',

                onPressed:
                    () {

                  _playAiResponse(
                    filePath,
                  );
                },
              ),


              const SizedBox(
                width:
                    14,
              ),


              // ==================================================
              // SHARE
              // ==================================================

              IconButton(

                padding:
                    EdgeInsets.zero,

                constraints:
                    const BoxConstraints(),

                icon:
                    const Icon(
                  Icons.share,
                  color:
                      Colors.green,
                  size:
                      25,
                ),

                tooltip:
                    'Share AI Response',

                onPressed:
                    () {

                  _shareAiResponse(
                    filePath,
                  );
                },
              ),


              const SizedBox(
                width:
                    12,
              ),


              // ==================================================
              // DELETE
              // ==================================================

              IconButton(

                padding:
                    EdgeInsets.zero,

                constraints:
                    const BoxConstraints(),

                icon:
                    const Icon(
                  Icons.delete_outline,
                  color:
                      Colors.redAccent,
                  size:
                      25,
                ),

                tooltip:
                    'Delete',

                onPressed:
                    () {

                  _deleteAiResponse(
                    filePath,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {

    _audioPlayer
        .dispose();


    super.dispose();
  }
}