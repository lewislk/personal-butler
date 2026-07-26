package service

import (
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/lewis/personal-butler/internal/dto"
	"github.com/lewis/personal-butler/internal/model"
	"gorm.io/gorm"
)

// ErrNoBackup 该 device 尚未上传过任何数据。
var ErrNoBackup = errors.New("no backup for device")

// ErrSyncInProgress 同一 deviceID 已经有一次写请求（upload/clear）在跑，
// 拒绝并发进入，避免"DELETE + INSERT"事务互相踩踏导致数据残缺。
// 客户端应当把按钮 disabled 并等上一次结束后再重试。
var ErrSyncInProgress = errors.New("sync in progress for device")

type SyncService struct {
	db *gorm.DB
	// deviceLocks 每个 deviceID 一把互斥锁；进程内单飞。
	// value: *sync.Mutex（LoadOrStore 保证只创建一份）。
	// MVP 单进程部署下这已足够；将来多副本再换 Redis SETNX / DB 咨询锁。
	deviceLocks sync.Map
}

func NewSyncService(db *gorm.DB) *SyncService { return &SyncService{db: db} }

// lockFor 拿到 deviceID 对应的 mutex（不存在则原子创建）。
func (s *SyncService) lockFor(deviceID string) *sync.Mutex {
	if v, ok := s.deviceLocks.Load(deviceID); ok {
		return v.(*sync.Mutex)
	}
	v, _ := s.deviceLocks.LoadOrStore(deviceID, &sync.Mutex{})
	return v.(*sync.Mutex)
}

// Upload 全量覆盖：先按 deviceID 清空该设备的所有业务表，再批量插入新的 payload。
// 语义与客户端「MVP 全量覆盖」一致；整个过程在一个事务内。
//
// 并发保护：同一 deviceID 用 TryLock 单飞。抢不到就返回 ErrSyncInProgress，
// 上游转 code=2003 让客户端在 UI 上提示"上一次同步还在进行"。
func (s *SyncService) Upload(deviceID string, p *dto.SyncPayload) error {
	mu := s.lockFor(deviceID)
	if !mu.TryLock() {
		return ErrSyncInProgress
	}
	defer mu.Unlock()

	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := clearDevice(tx, deviceID); err != nil {
			return err
		}
		if err := insertPayload(tx, deviceID, p); err != nil {
			return err
		}
		meta := model.SyncMetaRow{
			DeviceID:      deviceID,
			SyncTimestamp: p.SyncMeta.SyncTimestamp,
			AppVersion:    p.SyncMeta.AppVersion,
			DataVersion:   p.SyncMeta.DataVersion,
			UpdatedAt:     time.Now(),
		}
		// Save == UPDATE if PK exists else INSERT
		return tx.Save(&meta).Error
	})
}

// Download 组回一个完整 SyncPayload。若 sync_meta 里无该 device 记录，返回 ErrNoBackup。
func (s *SyncService) Download(deviceID string) (*dto.SyncPayload, error) {
	var meta model.SyncMetaRow
	if err := s.db.First(&meta, "device_id = ?", deviceID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrNoBackup
		}
		return nil, err
	}
	payload := &dto.SyncPayload{
		SyncMeta: dto.SyncMeta{
			DeviceID:      meta.DeviceID,
			SyncTimestamp: meta.SyncTimestamp,
			AppVersion:    meta.AppVersion,
			DataVersion:   meta.DataVersion,
		},
	}
	if err := loadPayload(s.db, deviceID, &payload.Data); err != nil {
		return nil, err
	}
	return payload, nil
}

// Info 返回摘要：sync_meta 行 + 该 device 的实体总条数。
func (s *SyncService) Info(deviceID string) (*dto.SyncInfo, error) {
	var meta model.SyncMetaRow
	if err := s.db.First(&meta, "device_id = ?", deviceID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrNoBackup
		}
		return nil, err
	}
	total, err := countAll(s.db, deviceID)
	if err != nil {
		return nil, err
	}
	return &dto.SyncInfo{
		DeviceID:      meta.DeviceID,
		SyncTimestamp: meta.SyncTimestamp,
		AppVersion:    meta.AppVersion,
		DataVersion:   meta.DataVersion,
		TotalCount:    total,
	}, nil
}

// Clear 删除该 device 的全部业务数据 + sync_meta 行。
// 同 Upload：走同一把 device 锁，避免和上传并发相互踩踏。
func (s *SyncService) Clear(deviceID string) error {
	mu := s.lockFor(deviceID)
	if !mu.TryLock() {
		return ErrSyncInProgress
	}
	defer mu.Unlock()

	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := clearDevice(tx, deviceID); err != nil {
			return err
		}
		return tx.Where("device_id = ?", deviceID).Delete(&model.SyncMetaRow{}).Error
	})
}

// ---------- 内部辅助 ----------

// deviceScopedTables 所有 (device_id, ...) 主键的业务表模型集合。
// 新增业务实体时在这里 + insertPayload + loadPayload + countAll 一起添加即可。
func deviceScopedTables() []any {
	return []any{
		&model.Todo{}, &model.Schedule{}, &model.Anniversary{},
		&model.Password{}, &model.OTP{},
		&model.Food{}, &model.Recipe{}, &model.CookIngredient{}, &model.CookCart{},
		&model.Note{},
		&model.AppModule{}, &model.AppSetting{},
	}
}

func clearDevice(tx *gorm.DB, deviceID string) error {
	for _, m := range deviceScopedTables() {
		if err := tx.Where("device_id = ?", deviceID).Delete(m).Error; err != nil {
			return err
		}
	}
	return nil
}

// joinStringSlice 把 []string 序列化为 JSON 数组字符串；nil → "" （DB 存 NULL）
func joinStringSlice(s []string) string {
	if s == nil {
		return ""
	}
	b, err := json.Marshal(s)
	if err != nil {
		return ""
	}
	return string(b)
}

// parseStringSlice 反向：JSON 数组字符串 → []string；空串 → nil
func parseStringSlice(s string) []string {
	if s == "" {
		return nil
	}
	var out []string
	if err := json.Unmarshal([]byte(s), &out); err != nil {
		return nil
	}
	return out
}

func insertPayload(tx *gorm.DB, deviceID string, p *dto.SyncPayload) error {
	d := &p.Data

	if len(d.TodoList) > 0 {
		rows := make([]model.Todo, 0, len(d.TodoList))
		for _, x := range d.TodoList {
			row := model.Todo{
				DeviceID: deviceID, ID: x.ID,
				Name: x.Name, Source: x.Source, DueDate: x.DueDate,
				IsDone: x.IsDone, CreatedAt: x.CreatedAt,
			}
			// v4 Optional 字段：指针拷贝
			row.TaskType = x.TaskType
			row.RecipeID = x.RecipeID
			if len(x.ExpectedIngredients) > 0 {
				s := joinStringSlice(x.ExpectedIngredients)
				row.ExpectedIngredients = &s
			}
			if len(x.CheckedIngredients) > 0 {
				s := joinStringSlice(x.CheckedIngredients)
				row.CheckedIngredients = &s
			}
			rows = append(rows, row)
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.ScheduleList) > 0 {
		rows := make([]model.Schedule, 0, len(d.ScheduleList))
		for _, x := range d.ScheduleList {
			rows = append(rows, model.Schedule{
				DeviceID: deviceID, ID: x.ID,
				Title: x.Title, Remark: x.Remark,
				StartDate: x.StartDate, EndDate: x.EndDate,
				IsAllDay: x.IsAllDay, ReminderMinutesBefore: x.ReminderMinutesBefore,
				ColorTag: x.ColorTag, IsCompleted: x.IsCompleted,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.AnniversaryList) > 0 {
		rows := make([]model.Anniversary, 0, len(d.AnniversaryList))
		for _, x := range d.AnniversaryList {
			rows = append(rows, model.Anniversary{
				DeviceID: deviceID, ID: x.ID,
				Name: x.Name, Date: x.Date, IsLunar: x.IsLunar, Type: x.Type,
				ReminderDaysBefore: x.ReminderDaysBefore, Emoji: x.Emoji,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.PasswordList) > 0 {
		rows := make([]model.Password, 0, len(d.PasswordList))
		for _, x := range d.PasswordList {
			rows = append(rows, model.Password{
				DeviceID: deviceID, ID: x.ID,
				Platform: x.Platform, Account: x.Account,
				TypeText: x.TypeText, Category: x.Category,
				PasswordPlain: x.PasswordPlain, UpdatedAt: x.UpdatedAt,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.OTPList) > 0 {
		rows := make([]model.OTP, 0, len(d.OTPList))
		for _, x := range d.OTPList {
			rows = append(rows, model.OTP{
				DeviceID: deviceID, ID: x.ID,
				Issuer: x.Issuer, AccountName: x.AccountName,
				SecretPlain: x.SecretPlain,
				Period:      x.Period, Digits: x.Digits, OrderIdx: x.Order,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.FoodRecordList) > 0 {
		rows := make([]model.Food, 0, len(d.FoodRecordList))
		for _, x := range d.FoodRecordList {
			tags, _ := json.Marshal(x.Tags)
			rows = append(rows, model.Food{
				DeviceID: deviceID, ID: x.ID,
				Name: x.Name, Emoji: x.Emoji, Rating: x.Rating,
				Tags: string(tags), Remark: x.Remark,
				Date: x.Date, Category: x.Category,
				// v2 位置 / v3 图片
				PlaceName: x.PlaceName, Address: x.Address,
				Latitude: x.Latitude, Longitude: x.Longitude,
				IconImageBase64: x.IconImageBase64,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	// cook_recipe + cook_ingredient：先建 recipe 拿到 id，再批量建 ingredient
	if len(d.CookRecipeList) > 0 {
		rows := make([]model.Recipe, 0, len(d.CookRecipeList))
		for _, x := range d.CookRecipeList {
			rows = append(rows, model.Recipe{
				DeviceID: deviceID, ID: x.ID,
				Name: x.Name, Emoji: x.Emoji, Difficulty: x.Difficulty,
				Minutes: x.Minutes, Category: x.Category,
				IngredientsLegacyRaw: x.IngredientsLegacyRaw,
				Steps: x.Steps, Tips: x.Tips,
				IconImageBase64: x.IconImageBase64,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}

		// 收集所有 ingredient 扁平成一批插入（recipe_id 取自 DTO）
		ingRows := make([]model.CookIngredient, 0, len(d.CookRecipeList)*4)
		for _, x := range d.CookRecipeList {
			for _, ing := range x.Ingredients {
				ingRows = append(ingRows, model.CookIngredient{
					DeviceID: deviceID, ID: ing.ID,
					RecipeID: x.ID, Name: ing.Name,
					Amount: ing.Amount, OrderIdx: ing.Order,
				})
			}
		}
		if len(ingRows) > 0 {
			if err := tx.CreateInBatches(ingRows, 200).Error; err != nil {
				return err
			}
		}
	}

	// cook_cart：v4 新增
	if len(d.CartList) > 0 {
		rows := make([]model.CookCart, 0, len(d.CartList))
		for _, x := range d.CartList {
			rows = append(rows, model.CookCart{
				DeviceID: deviceID, ID: x.ID,
				RecipeID: x.RecipeID, Servings: x.Servings, AddedAt: x.AddedAt,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.NoteList) > 0 {
		rows := make([]model.Note, 0, len(d.NoteList))
		for _, x := range d.NoteList {
			rows = append(rows, model.Note{
				DeviceID: deviceID, ID: x.ID,
				Title: x.Title, Content: x.Content, Tag: x.Tag,
				CreatedAt: x.CreatedAt, UpdatedAt: x.UpdatedAt,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.AppModuleList) > 0 {
		rows := make([]model.AppModule, 0, len(d.AppModuleList))
		for _, x := range d.AppModuleList {
			rows = append(rows, model.AppModule{
				DeviceID: deviceID, ID: x.ID,
				Name: x.Name, Tag: x.Tag, IconSystemName: x.IconSystemName,
				OrderIdx: x.Order, ComingSoon: x.ComingSoon,
			})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	if len(d.Setting) > 0 {
		rows := make([]model.AppSetting, 0, len(d.Setting))
		for k, v := range d.Setting {
			rows = append(rows, model.AppSetting{DeviceID: deviceID, Key: k, Value: v})
		}
		if err := tx.CreateInBatches(rows, 200).Error; err != nil {
			return err
		}
	}

	return nil
}

func loadPayload(db *gorm.DB, deviceID string, out *dto.SyncData) error {
	// 初始化空切片而不是 nil，让 JSON 序列化出 `[]` 而不是 `null`（对齐客户端 Codable 期望）
	out.TodoList = []dto.SyncTodoDTO{}
	out.ScheduleList = []dto.SyncScheduleDTO{}
	out.AnniversaryList = []dto.SyncAnniDTO{}
	out.PasswordList = []dto.SyncPasswordDTO{}
	out.OTPList = []dto.SyncOTPDTO{}
	out.FoodRecordList = []dto.SyncFoodDTO{}
	out.CookRecipeList = []dto.SyncRecipeDTO{}
	out.CartList = []dto.SyncCartDTO{}
	out.NoteList = []dto.SyncNoteDTO{}
	out.AppModuleList = []dto.SyncModuleDTO{}
	out.Setting = map[string]string{}

	var todos []model.Todo
	if err := db.Where("device_id = ?", deviceID).Find(&todos).Error; err != nil {
		return err
	}
	for _, x := range todos {
		row := dto.SyncTodoDTO{
			ID: x.ID, Name: x.Name, Source: x.Source,
			DueDate: x.DueDate, IsDone: x.IsDone, CreatedAt: x.CreatedAt,
			// v4 Optional 字段
			TaskType: x.TaskType, RecipeID: x.RecipeID,
		}
		if x.ExpectedIngredients != nil {
			row.ExpectedIngredients = parseStringSlice(*x.ExpectedIngredients)
		}
		if x.CheckedIngredients != nil {
			row.CheckedIngredients = parseStringSlice(*x.CheckedIngredients)
		}
		out.TodoList = append(out.TodoList, row)
	}

	var schedules []model.Schedule
	if err := db.Where("device_id = ?", deviceID).Find(&schedules).Error; err != nil {
		return err
	}
	for _, x := range schedules {
		out.ScheduleList = append(out.ScheduleList, dto.SyncScheduleDTO{
			ID: x.ID, Title: x.Title, Remark: x.Remark,
			StartDate: x.StartDate, EndDate: x.EndDate, IsAllDay: x.IsAllDay,
			ReminderMinutesBefore: x.ReminderMinutesBefore,
			ColorTag:              x.ColorTag, IsCompleted: x.IsCompleted,
		})
	}

	var annis []model.Anniversary
	if err := db.Where("device_id = ?", deviceID).Find(&annis).Error; err != nil {
		return err
	}
	for _, x := range annis {
		out.AnniversaryList = append(out.AnniversaryList, dto.SyncAnniDTO{
			ID: x.ID, Name: x.Name, Date: x.Date, IsLunar: x.IsLunar,
			Type: x.Type, ReminderDaysBefore: x.ReminderDaysBefore, Emoji: x.Emoji,
		})
	}

	var pws []model.Password
	if err := db.Where("device_id = ?", deviceID).Find(&pws).Error; err != nil {
		return err
	}
	for _, x := range pws {
		out.PasswordList = append(out.PasswordList, dto.SyncPasswordDTO{
			ID: x.ID, Platform: x.Platform, Account: x.Account,
			TypeText: x.TypeText, Category: x.Category,
			PasswordPlain: x.PasswordPlain, UpdatedAt: x.UpdatedAt,
		})
	}

	var otps []model.OTP
	if err := db.Where("device_id = ?", deviceID).Order("order_idx asc").Find(&otps).Error; err != nil {
		return err
	}
	for _, x := range otps {
		out.OTPList = append(out.OTPList, dto.SyncOTPDTO{
			ID: x.ID, Issuer: x.Issuer, AccountName: x.AccountName,
			SecretPlain: x.SecretPlain, Period: x.Period, Digits: x.Digits, Order: x.OrderIdx,
		})
	}

	var foods []model.Food
	if err := db.Where("device_id = ?", deviceID).Find(&foods).Error; err != nil {
		return err
	}
	for _, x := range foods {
		var tags []string
		if x.Tags != "" {
			_ = json.Unmarshal([]byte(x.Tags), &tags)
		}
		if tags == nil {
			tags = []string{}
		}
		out.FoodRecordList = append(out.FoodRecordList, dto.SyncFoodDTO{
			ID: x.ID, Name: x.Name, Emoji: x.Emoji, Rating: x.Rating,
			Tags: tags, Remark: x.Remark, Date: x.Date, Category: x.Category,
			// v2 位置 / v3 图片
			PlaceName: x.PlaceName, Address: x.Address,
			Latitude: x.Latitude, Longitude: x.Longitude,
			IconImageBase64: x.IconImageBase64,
		})
	}

	// cook_recipe + cook_ingredient：先查 recipe，再查该 device 全部 ingredient 按 recipe_id 分组
	var recipes []model.Recipe
	if err := db.Where("device_id = ?", deviceID).Find(&recipes).Error; err != nil {
		return err
	}
	var allIngs []model.CookIngredient
	if err := db.Where("device_id = ?", deviceID).Order("order_idx asc").Find(&allIngs).Error; err != nil {
		return err
	}
	ingByRecipe := make(map[string][]dto.SyncIngredientDTO, len(recipes))
	for _, ing := range allIngs {
		ingByRecipe[ing.RecipeID] = append(ingByRecipe[ing.RecipeID], dto.SyncIngredientDTO{
			ID: ing.ID, Name: ing.Name, Amount: ing.Amount, Order: ing.OrderIdx,
		})
	}
	for _, x := range recipes {
		ings := ingByRecipe[x.ID]
		if ings == nil {
			ings = []dto.SyncIngredientDTO{}
		}
		out.CookRecipeList = append(out.CookRecipeList, dto.SyncRecipeDTO{
			ID: x.ID, Name: x.Name, Emoji: x.Emoji, Difficulty: x.Difficulty,
			Minutes: x.Minutes, Category: x.Category,
			IngredientsLegacyRaw: x.IngredientsLegacyRaw,
			Ingredients:          ings,
			Steps:                x.Steps, Tips: x.Tips,
			IconImageBase64: x.IconImageBase64,
		})
	}

	// cook_cart：v4 新增
	var carts []model.CookCart
	if err := db.Where("device_id = ?", deviceID).Order("added_at asc").Find(&carts).Error; err != nil {
		return err
	}
	for _, x := range carts {
		out.CartList = append(out.CartList, dto.SyncCartDTO{
			ID: x.ID, RecipeID: x.RecipeID, Servings: x.Servings, AddedAt: x.AddedAt,
		})
	}

	var notes []model.Note
	if err := db.Where("device_id = ?", deviceID).Find(&notes).Error; err != nil {
		return err
	}
	for _, x := range notes {
		out.NoteList = append(out.NoteList, dto.SyncNoteDTO{
			ID: x.ID, Title: x.Title, Content: x.Content, Tag: x.Tag,
			CreatedAt: x.CreatedAt, UpdatedAt: x.UpdatedAt,
		})
	}

	var mods []model.AppModule
	if err := db.Where("device_id = ?", deviceID).Order("order_idx asc").Find(&mods).Error; err != nil {
		return err
	}
	for _, x := range mods {
		out.AppModuleList = append(out.AppModuleList, dto.SyncModuleDTO{
			ID: x.ID, Name: x.Name, Tag: x.Tag, IconSystemName: x.IconSystemName,
			Order: x.OrderIdx, ComingSoon: x.ComingSoon,
		})
	}

	var settings []model.AppSetting
	if err := db.Where("device_id = ?", deviceID).Find(&settings).Error; err != nil {
		return err
	}
	for _, x := range settings {
		out.Setting[x.Key] = x.Value
	}
	return nil
}

func countAll(db *gorm.DB, deviceID string) (int64, error) {
	var total int64
	for _, m := range deviceScopedTables() {
		// AppSetting 复合主键是 (device_id, key)，也算实体数
		var c int64
		if err := db.Model(m).Where("device_id = ?", deviceID).Count(&c).Error; err != nil {
			return 0, err
		}
		total += c
	}
	return total, nil
}
