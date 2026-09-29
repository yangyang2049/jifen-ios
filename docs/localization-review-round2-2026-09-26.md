# 本地化第二轮逐项检查（2026-09-26）

本轮聚焦按钮、目录、短标签和窄屏显示，修正 218 处地区语言文案，并同步更新审核目录与正式资源。没有调用机器翻译服务。

## 实际覆盖范围

- 日语、韩语、德语、法语（法国／加拿大）、俄语、阿拉伯语：逐项对照 739 个按钮、目录和短标签 key。
- 西班牙语（西班牙／墨西哥）、葡萄牙语（巴西／葡萄牙）：扩展至 1,048 个短文案 key。
- 共 9,365 条语言与 key 对照，逐项记录见 `build/localization/round2/reviewed-rows.jsonl`。
- 11 个地区版本每个 1,401 个普通字符串，以及复数、权限说明资源均做结构验证。长篇 FAQ、协议全文及所有比分状态不属于本轮逐句人工验收范围，不能把本报告视为全应用所有文字、页面已验收。

## 主要修正

- 西语 `Partitura principal derecha`（右侧乐谱）改为右侧主比分；`Puntuación correcta...` 中把 right 当作“正确”的错误已修正。
- 掼蛋“双上”统一表达同队取得第 1、2 名（+3），去除含糊的“Double Up／双胜”直译。
- 俄语三／五／七局制明确表达“先取得 2／3／4 胜”，单局／单盘制不再直译为“最好的一个”。
- 葡萄牙葡语保存统一为 `Guardar`，秒表为 `Cronómetro`；巴西葡语篮球暂停由“时间上限”改为 `TEMPO TÉCNICO`。
- 日语未结束比赛改为“未終了”，预约时长改为“所要時間”；开局预设在日、德、西、阿语中由动词命令改为设置项名称。
- 阿语斗地主倍数恢复数学符号 `×`，篮球节次改为“第几节”，两分按钮修复双数语法。
- 法语、俄语、韩语设置标题后缀补上分隔，避免拼成 `ÉchecsConfiguration` 一类连字标题。

## 长按钮优化示例

| 地区 | 旧文案 | 新文案 | 上下文 |
| --- | --- | --- | --- |
| 葡语 | Gerar código novamente | Novo código | 同步页重新生成代码 |
| 葡语 | Classificação | Pos. | 排名表窄列标题 |
| 葡语 | Escolha os jogadores novamente | Trocar jogadores | 随机分组重选玩家 |
| 西语 | Entrenamiento de tiro | Práctica de tiro | 投篮训练入口 |
| 西语 | Ver todos los registros | Ver todos | 最近记录区域按钮 |
| 葡语 | Assinatura mensal | Mensal | 会员页方案按钮 |
| 日语 | トレーニングを終了する | 練習終了 | 结束训练按钮 |

没有为了缩短而删掉删除账号、清空数据等破坏性操作的关键含义；辅助功能标签保持必要描述。

## 布局修复

1. 计分／计时目录、快速开始卡片和运动选择器支持两行标签；计分与计时目录预留两行高度。
2. 工具入口支持两行，横向工具栏同步增高，避免文字被外层固定高度裁掉。
3. 常用名称／地点根据实际文字宽度在并排卡片和整行卡片间切换，保留说明文字，取消只对英语生效的特例。
4. “我的”副标题、手机会员方案文字允许纵向展开；价格保持完整。未登录标题支持两行，避免日语的否定词被截掉。
5. 棋牌操作按钮允许两行；登录协议链接之间增加间隔。
6. “我的”、工具入口及选手选择行改用方向语义箭头，阿语下箭头正确朝左。
7. 棋类计时设置导航标题支持两行；俄语计时增量选项改为简洁的 `Добавка`，避免窄屏分段控件截断。

## 验证与证据

- Python 本地化流水线测试：14 项通过。
- 11 个地区审核门禁：零阻断；正式资源与目录重新渲染的内容一致；33 个资源文件通过 plutil。
- iPhone 17e：11 个地区、7 个页面位置，共 77 张截图，流程通过。
- iPad Pro 11：西语／葡语 4 个地区、7 个页面位置，共 28 张截图，流程通过。
- iPhone SE（375 点宽）：11 个地区、10 个页面位置，共 110 张截图，目录、设置、登录和掼蛋场景流程通过。最后的账户标题／计时标题修复另跑 11 个地区复测并通过，22 张截图替换为最终版本。
- Xcode 编译通过；19 项本地化完整性测试、64 项记录回归测试（共 83 项）全部通过。
- 截图与 xcresult：`build/localization/round2/`。截图流程通过仅证明可进入页面；具体目视检查范围在下方记录。
- iPad 首页现存的自定义队名（例如中文队名）保留，不把用户数据当成翻译错误，也不为清理截图删除用户记录；自动截图仅清除测试自建的 `ui-fixture-*` 记录。
- 本轮未运行真机、iPad 分屏、横屏和所有动态字体档位；旧报告中的 FAQ Miracast 源文案问题不在本轮按钮修复中关闭。

## 目视检查与限制

- 检查了德语目录长标签、会员说明；日语首页与登录；巴西葡语首页、会员方案、投篮训练；葡萄牙葡语计时目录与 iPad 首页；西语个人页和掼蛋设置；法语登录协议；韩语和阿语登录；阿语个人页箭头；小屏德／法／俄／西／葡／阿语棋类计时设置。
- 西葡语目录中“倒计时”“投篮训练”等长词可完整换行，会员方案采用短标题；未把 215 张截图的自动生成等同于逐张人工验收。
- 新建 SE 模拟器的会员商品处于加载状态，因此这台设备的会员方案按钮排版未完成目视验收；已加载的 iPhone 17e 和 iPad 会员页已检查。
- 最终复测目视确认：日语未登录标题的否定词完整显示；德语、法语、俄语、西语和葡语棋类计时标题完整换行；俄语增量选项 `Добавка` 无截断。

## 逐项修订清单

| 地区 | Key | 修订前 | 修订后 |
| --- | --- | --- | --- |
| ja | home_view_all_records | すべての記録を表示 | すべて見る |
| ja | guandan_pass_a_double_up | ダブルアップ (+3) | 1位・2位 (+3) |
| ja | time_filter | 時間 | 期間 |
| ja | common_places_title | よくある場所 | よく使う場所 |
| ja | menu_swap_sides | サイドを入れ替える | サイド交代 |
| ja | scoreboard_style_center_team_name | センターチーム名 | 中央のチーム名 |
| ja | scoreboard_style_center_main_score | センターメインスコア | 中央のメインスコア |
| ko | home_view_all_records | 모든 기록 보기 | 전체 보기 |
| ko | guandan_pass_a_double_up | 더블 업 (+3) | 1·2위 (+3) |
| ko | time_filter | 시간 | 기간 |
| ko | shengji_claim_dealer | 입찰 딜러 | 딜러 선점 |
| ko | shengji_take_dealer | 테이크 딜러 | 딜러 맡기 |
| ko | snooker_foul_switch_turn | 공수 교대 | 차례 넘기기 |
| de | home_view_all_records | Gesamten Verlauf anzeigen | Alle anzeigen |
| de | time_filter | Zeit | Zeitraum |
| de | menu_undo | Rückgängig machen | Rückgängig |
| de | undo | Rückgängig machen | Rückgängig |
| de | tool_ten_second | 10-Sekunden-Challenge | 10-Sekunden-Test |
| de | ten_second_title | 10-Sekunden-Challenge | 10-Sekunden-Test |
| fr | home_view_all_records | Afficher tout l’historique | Tout voir |
| fr | guandan_pass_a_double_up | Double montée (+3) | 1re et 2e places (+3) |
| fr | try_again | Réessayez | Réessayer |
| fr | game_badminton_doubles | Doubles de badminton | Double de badminton |
| fr | game_badminton_singles | Simples de badminton | Simple de badminton |
| fr | game_pingpong_singles | Simples de tennis de table | Simple de tennis de table |
| fr | scoreboard_double_tap_subtract | Appuyez deux fois sur −1 | Double toucher : −1 |
| fr | scoreboard_double_tap_help_title | Appuyez deux fois sur −1 | Double toucher : −1 |
| fr-CA | home_view_all_records | Afficher tout l’historique | Tout voir |
| fr-CA | try_again | Réessayez | Réessayer |
| fr-CA | scoreboard_double_tap_subtract | Touchez deux fois pour −1 | Double toucher : −1 |
| fr-CA | scoreboard_double_tap_help_title | Touchez deux fois pour −1 | Double toucher : −1 |
| es-ES | home_view_all_records | Ver todos los registros | Ver todos |
| es-ES | guandan_pass_a_double_up | Doble victoria (+3) | 1.º y 2.º puestos (+3) |
| es-ES | time_filter | Tiempo | Período |
| es-ES | try_again | Volver a intentarlo | Reintentar |
| es-ES | game_basketball_training | Entrenamiento de tiro | Práctica de tiro |
| es-ES | shot_training_setup_title | Entrenamiento de tiro | Práctica de tiro |
| es-ES | shot_training_finish | Finalizar entrenamiento | Finalizar práctica |
| es-ES | timer_custom_minutes | Mín. | Min |
| es-ES | schedule_duration_short | %d mín. | %d min |
| es-ES | random_team_reselect | Volver a elegir jugadores | Cambiar jugadores |
| es-ES | game_soft_tennis | Tenis suave | Soft tenis |
| es-ES | scoreboard_style_right_main_score | Partitura principal derecha | Marcador principal derecho |
| es-ES | scoreboard_style_left_set_score | Puntuación del conjunto izquierdo | Sets de la izquierda |
| es-ES | scoreboard_style_right_set_score | Marcador de set derecho | Sets de la derecha |
| es-ES | scoreboard_style_left_set_games_score | Puntuación del juego/conjunto izquierdo | Sets/juegos de la izquierda |
| es-ES | scoreboard_style_right_set_games_score | Puntuación correcta del juego/conjunto | Sets/juegos de la derecha |
| es-ES | scoreboard_style_snooker_left_break_score | Puntuación de quiebre izquierdo | Puntos de la serie izquierda |
| es-ES | scoreboard_style_snooker_right_break_score | Puntuación de quiebre derecho | Puntos de la serie derecha |
| es-ES | sync_role_scorer_title | Iniciar sincronización de puntuación | Iniciar sincronización |
| es-ES | sync_role_viewer_title | Unirse a la sincronización de puntuaciones | Unirse a sincronización |
| es-ES | sync_login_create_room | Crear código de sincronización | Crear código |
| es-ES | sync_login_and_create_room | Iniciar sesión y crear código de sincronización | Iniciar sesión y crear código |
| es-ES | sync_retry_shortcode | Regenerar código | Nuevo código |
| es-ES | feedback_report_spam | Correo no deseado | Spam |
| es-ES | membership_monthly_plan_title | Membresía mensual | Mensual |
| es-ES | membership_yearly_plan_title | Membresía anual | Anual |
| es-ES | membership_lifetime_plan_title | Membresía vitalicia | De por vida |
| es-ES | timer_timeout | Cuenta regresiva | Cuenta atrás |
| es-ES | timer_sport_preset_timeout | Tiempo de espera | Tiempo muerto |
| es-ES | record_detail_synced_from_watch_badge | Ver registro sincronizado | Registro del reloj sincronizado |
| es-ES | setup_snooker_break_left | El lado izquierdo rompe el primer cuadro | El lado izquierdo hace el saque inicial |
| es-ES | score_custom_adjust_increment | Agregar | Añadir |
| es-ES | feedback_form_add_images | Agregar imágenes | Añadir imágenes |
| es-ES | me_profile_membership_number_label | N. º de socio | N.º de socio |
| es-MX | home_view_all_records | Ver todos los registros | Ver todos |
| es-MX | guandan_pass_a_double_up | Doble victoria (+3) | 1.º y 2.º lugares (+3) |
| es-MX | time_filter | Tiempo | Período |
| es-MX | try_again | Intentar de nuevo | Reintentar |
| es-MX | game_basketball_training | Entrenamiento de tiro | Práctica de tiro |
| es-MX | shot_training_setup_title | Entrenamiento de tiro | Práctica de tiro |
| es-MX | shot_training_finish | Finalizar entrenamiento | Finalizar práctica |
| es-MX | timer_custom_minutes | Mín. | Min |
| es-MX | schedule_duration_short | %d mín. | %d min |
| es-MX | random_team_reselect | Volver a elegir jugadores | Cambiar jugadores |
| es-MX | game_soft_tennis | Tenis suave | Soft tenis |
| es-MX | scoreboard_style_right_main_score | Partitura principal derecha | Marcador principal derecho |
| es-MX | scoreboard_style_left_set_score | Puntuación del conjunto izquierdo | Sets de la izquierda |
| es-MX | scoreboard_style_right_set_score | Marcador de set derecho | Sets de la derecha |
| es-MX | scoreboard_style_left_set_games_score | Puntuación del juego/conjunto izquierdo | Sets/juegos de la izquierda |
| es-MX | scoreboard_style_right_set_games_score | Marcador de set/juego derecho | Sets/juegos de la derecha |
| es-MX | scoreboard_style_snooker_left_break_score | Puntuación de quiebre izquierdo | Puntos de la serie izquierda |
| es-MX | scoreboard_style_snooker_right_break_score | Puntuación de quiebre derecho | Puntos de la serie derecha |
| es-MX | sync_role_scorer_title | Iniciar sincronización de puntuación | Iniciar sincronización |
| es-MX | sync_role_viewer_title | Unirse a la sincronización de puntuaciones | Unirse a sincronización |
| es-MX | sync_login_create_room | Crear código de sincronización | Crear código |
| es-MX | sync_login_and_create_room | Iniciar sesión y crear código de sincronización | Iniciar sesión y crear código |
| es-MX | sync_retry_shortcode | Regenerar código | Nuevo código |
| es-MX | feedback_report_spam | Correo no deseado | Spam |
| es-MX | membership_monthly_plan_title | Membresía mensual | Mensual |
| es-MX | membership_yearly_plan_title | Membresía anual | Anual |
| es-MX | membership_lifetime_plan_title | Membresía vitalicia | De por vida |
| es-MX | game_basketball | Baloncesto | Basquetbol |
| pt-BR | home_view_all_records | Ver todos os registros | Ver todos |
| pt-BR | guandan_pass_a_double_up | Dupla vitória (+3) | 1.º e 2.º lugares (+3) |
| pt-BR | time_filter | Tempo | Período |
| pt-BR | points_table_rank | Classificação | Pos. |
| pt-BR | try_again | Tente novamente | Tentar de novo |
| pt-BR | retry | Tentar novamente | Tentar de novo |
| pt-BR | random_team_reselect | Escolha os jogadores novamente | Trocar jogadores |
| pt-BR | shot_training_finish | Concluir treinamento | Concluir treino |
| pt-BR | scoreboard_double_tap_subtract | Toque duas vezes em −1 | Toque duplo: −1 |
| pt-BR | scoreboard_double_tap_help_title | Toque duas vezes em −1 | Toque duplo: −1 |
| pt-BR | sync_role_scorer_title | Iniciar sincronização de pontuação | Iniciar sincronização |
| pt-BR | sync_login_create_room | Criar código de sincronização | Criar código |
| pt-BR | sync_retry_shortcode | Gerar código novamente | Novo código |
| pt-BR | feedback_platform_harmony | Harmony OS | HarmonyOS |
| pt-BR | voice_announcement_on | Voz: Ligado | Voz: ligada |
| pt-BR | voice_announcement_off | Voz: Desligado | Voz: desligada |
| pt-BR | membership_monthly_plan_title | Assinatura mensal | Mensal |
| pt-BR | membership_yearly_plan_title | Assinatura anual | Anual |
| pt-BR | membership_lifetime_plan_title | Assinatura vitalícia | Vitalício |
| pt-BR | auto_change_sides | Troca automática de lado | Troca automática |
| pt-BR | display_basketball_clock_pause | TEMPO LIMITE | TEMPO TÉCNICO |
| pt-BR | boxing_rounds | Rodadas | Assaltos |
| pt-BR | boxing_round_n | Rodada %d | Assalto %d |
| pt-BR | boxing_round_progress | Rodada %d/%d | Assalto %d/%d |
| pt-BR | boxing_end_round | Encerrar rodada | Encerrar assalto |
| pt-BR | team2_name | Nome do time visitante | Nome da equipe visitante |
| pt-BR | sync_login_and_create_room | Entrar e criar código de sincronização | Entrar e criar código |
| pt-PT | home_view_all_records | Ver todos os registos | Ver todos |
| pt-PT | guandan_pass_a_double_up | Dupla vitória (+3) | 1.º e 2.º lugares (+3) |
| pt-PT | time_filter | Tempo | Período |
| pt-PT | points_table_rank | Classificação | Pos. |
| pt-PT | try_again | Tente novamente | Tentar de novo |
| pt-PT | retry | Tentar novamente | Tentar de novo |
| pt-PT | random_team_reselect | Escolha os jogadores novamente | Trocar jogadores |
| pt-PT | scoreboard_double_tap_subtract | Toque duas vezes em −1 | Toque duplo: −1 |
| pt-PT | scoreboard_double_tap_help_title | Toque duas vezes em −1 | Toque duplo: −1 |
| pt-PT | sync_role_scorer_title | Iniciar sincronização de pontuação | Iniciar sincronização |
| pt-PT | sync_login_create_room | Criar código de sincronização | Criar código |
| pt-PT | sync_retry_shortcode | Gerar código novamente | Novo código |
| pt-PT | feedback_platform_harmony | Harmony OS | HarmonyOS |
| pt-PT | voice_announcement_on | Voz: Ligado | Voz: ligada |
| pt-PT | voice_announcement_off | Voz: Desligado | Voz: desligada |
| pt-PT | membership_monthly_plan_title | Subscrição mensal | Mensal |
| pt-PT | membership_yearly_plan_title | Subscrição anual | Anual |
| pt-PT | membership_lifetime_plan_title | Subscrição vitalícia | Vitalício |
| pt-PT | save | Salvar | Guardar |
| pt-PT | tab_score | Pontuação | Marcador |
| pt-PT | game_stopwatch | Cronômetro | Cronómetro |
| pt-PT | barrage_scroll_speed | Velocidade de rolagem | Velocidade de deslocamento |
| pt-PT | feedback_external_link_open | Abrir na mesma | Continuar |
| pt-PT | account_deletion_confirm_action | Confirmar exclusão | Confirmar eliminação |
| pt-PT | account_deletion_confirm_cancel | Manter minha conta | Manter a minha conta |
| pt-PT | account_deletion_submitting | Enviando... | A enviar... |
| pt-PT | feedback_form_guide_title | Dicas de postagem | Dicas de publicação |
| pt-PT | sync_login_and_create_room | Iniciar sessão e criar código de sincronização | Iniciar sessão e criar código |
| ru | home_view_all_records | Просмотреть все записи | Все записи |
| ru | retry | Повторить попытку. | Повторить |
| ru | try_again | Попробовать ещё раз | Ещё раз |
| ru | tool_red_yellow_card | Красная и жёлтая карточки | Карточки |
| ru | tool_ten_second | Испытание на 10 секунд | Испытание 10 с |
| ru | ten_second_title | Испытание на 10 секунд | Испытание 10 с |
| ru | game_multi_scoreboard | Счёт для нескольких игроков | Счёт игроков |
| ru | timer_sport_preset_tennis_set_break | Перерыв в сете | Перерыв между сетами |
| ar | home_view_all_records | عرض كافة السجلات | كل السجلات |
| ar | guandan_pass_a_double_up | فوز مزدوج (+3) | المركزان الأول والثاني (+3) |
| ar | time_filter | الوقت | الفترة |
| ar | basketball_timeout | المهلة | وقت مستقطع |
| ar | display_basketball_clock_pause | المهلة | وقت مستقطع |
| ar | scoreboard_style_center_main_score | النتيجة الرئيسية للمركز | النتيجة الرئيسية في الوسط |
| ar | menu_end_game | نهاية المباراة | إنهاء المباراة |
| ar | tool_aa_calculator | حاسبة تقسيم الفاتورة | تقسيم الفاتورة |
| ar | tool_ten_second | تحدي العشر ثواني | تحدي 10 ثوانٍ |
| ar | ten_second_title | تحدي العشر ثواني | تحدي 10 ثوانٍ |
| ar | game_basketball_training | التدريب على التسديد | تدريب التسديد |
| ar | shot_training_setup_title | التدريب على التسديد | تدريب التسديد |
| ja | shot_training_finish | トレーニングを終了する | 練習終了 |
| ja | unfinished | 未完成 | 未終了 |
| ja | record_unfinished | 未完成 | 未終了 |
| ja | schedule_duration | 期間 | 所要時間 |
| ja | schedule_start_preset | プリセットを開始 | 開始時の設定 |
| ja | common_places_select | 場所を選択してください | 場所を選択 |
| ja | account_login_agreement_prefix | 読み、同意します | 以下を読み、同意します： |
| ja | shengji_dealer | ディーラー | 親 |
| ko | setup_suffix | 설정 | : 설정 |
| ko | snooker_handover | 공수 교대 | 차례 넘기기 |
| ko | shengji_dealer | 선 | 딜러 |
| ko | doudizhu_multiplier | 승수 | 배수 |
| de | schedule_start_preset | Mit Voreinstellung starten | Starteinstellungen |
| fr | setup_suffix | Configuration | : configuration |
| fr | dialog_new_game_title | Choisir un sport | Choisir un jeu |
| fr | doubles | Doubles | Double |
| fr | random_team_reselect | Choisissez à nouveau les joueurs | Changer de joueurs |
| fr | pingpong_set_option_best_of_1 | Au meilleur d’1 | 1 manche |
| fr | tennis_set_option_best_of_1 | Au meilleur d’1 | 1 set |
| fr | shengji_claim_dealer | Enchérir comme donneur | Devenir donneur |
| fr-CA | setup_suffix | Configuration | : configuration |
| fr-CA | dialog_new_game_title | Choisir un sport | Choisir un jeu |
| fr-CA | doubles | Doubles | Double |
| fr-CA | random_team_reselect | Choisissez à nouveau les joueurs | Changer de joueurs |
| fr-CA | pingpong_set_option_best_of_1 | Meilleur de 1 | 1 manche |
| fr-CA | tennis_set_option_best_of_1 | Meilleur de 1 | 1 set |
| fr-CA | shengji_claim_dealer | Miser pour devenir donneur | Devenir donneur |
| es-ES | schedule_start_preset | Iniciar preajuste | Ajustes iniciales |
| es-MX | schedule_start_preset | Iniciar preajuste | Ajustes iniciales |
| ru | setup_suffix | Настройка | : настройки |
| ru | official_break_set | Перерыв в сете | Перерыв между сетами |
| ru | shengji_claim_dealer | Заявить раздающего | Стать раздающим |
| ru | pingpong_set_option_best_of_3 | Лучшее из 3 | До 2 побед |
| ru | pingpong_set_option_best_of_5 | Лучшее из 5 | До 3 побед |
| ru | pingpong_set_option_best_of_7 | Лучшее из 7 | До 4 побед |
| ru | tennis_set_option_best_of_3 | Лучшее из 3 | До 2 побед |
| ru | tennis_set_option_best_of_5 | Лучшее из 5 | До 3 побед |
| ru | pingpong_set_option_best_of_1 | Лучшее из 1 | Одна партия |
| ru | tennis_set_option_best_of_1 | Лучшее из 1 | Один сет |
| ar | shot_training_2pt | 2 نقطة | نقطتان |
| ar | schedule_start_preset | ابدأ الإعداد المسبق | إعدادات البداية |
| ar | doudizhu_fan_suffix | س | × |
| ar | display_basketball_period | س%d | الربع %d |
| ar | chase_chalk_normal | دبليو | فوز |
| ar | membership_redeem_offer_code | استرداد | استخدام رمز |
| ar | scoreboard_font_metric_secondary | مجموعات/ألعاب | مجموعات/أشواط |
| ar | pingpong_set_option_best_of_1 | مباراة واحدة | شوط واحد |
| ar | records_batch_deselect_all | قم بإلغاء تحديد الكل | إلغاء تحديد الكل |
| ar | deselect_all | قم بإلغاء تحديد الكل | إلغاء تحديد الكل |
| ru | timer_increment | Добавление времени | Добавка |

## 后续调整：首页投屏入口简化

按用户反馈，手机和平板首页统一复用简短的投屏标签（西语 `Emitir / Transmitir`、葡语 `Transmitir`），单行完整显示；详情页继续保留投屏与跨设备同步，辅助功能仍描述完整入口用途。后续按用户反馈，简中、繁中和韩语保留“投屏与同步”的完整标题，其余语言使用短标题。顺带修正希伯来语投屏标签把 cast 错译成演员的问题，改为 `שידור`，目录与资源已同步。

本次增量编译通过，希伯来语资源审核通过；生成 11 个语言地区的小屏首页截图、2 张西葡语 iPad 首页截图，目视确认西葡语、德语、俄语和希伯来语小屏按钮以及葡语 iPad 按钮完整单行显示。证据位于 `build/localization/home-cast-short/`。
