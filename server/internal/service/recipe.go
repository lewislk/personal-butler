package service

import (
	"crypto/rand"
	"errors"
	"fmt"
	"time"

	"github.com/lewis/personal-butler/internal/dto"
	"github.com/lewis/personal-butler/internal/model"
	"gorm.io/gorm"
)

// RecipeService 提供 Web 表单录入菜谱所需的 CRUD 能力。
//
// 与 sync.go 的全量覆盖语义不同：本服务按单条 recipe 增删改，方便 Web 表单
// 直接写入 DB。iOS 客户端后续走 /sync/download → restore 即可把数据拉到本地。
//
// 重要约定：
//   - 所有写入都关联到调用方提交的 deviceID（与 iOS X-Device-ID 同一命名空间）。
//   - 任何一次成功写入后，都会 upsert sync_meta 行，确保 iOS 客户端能 download
//     （download 在 sync_meta 行不存在时会返回 ErrNoBackup）。
//   - dataVersion 固定为当前 schema 版本（与 SyncPayload.swift 同步递增）。
type RecipeService struct {
	db *gorm.DB
}

func NewRecipeService(db *gorm.DB) *RecipeService { return &RecipeService{db: db} }

// 当前 schema 版本，与 iOS 端 SyncMeta.dataVersion 保持一致。
const currentDataVersion = 4

// Web 表单 CRUD 专用错误。
var (
	ErrRecipeNotFound  = errors.New("recipe not found")
	ErrRecipeIDMismatch = errors.New("recipe id in path does not match body")
)

// newUUID 生成与客户端 SwiftData UUID 同样格式的 v4 UUID 字符串。
// 用 crypto/rand 保证全局唯一性；与 iOS Foundation.UUID 字符串表示一致（小写带连字符）。
func newUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		// rand.Read 在加密场景几乎不会失败；失败时退化为基于时间戳的伪 UUID
		// 仅作兜底，不阻断流程
		return fmt.Sprintf("%012x", time.Now().UnixNano())
	}
	// RFC 4122 v4：version + variant 位
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// RecipeInput 是 Web 表单提交上来的菜谱结构。
// 与 SyncRecipeDTO 区别在于 ID 可空（创建时由服务端生成 UUID）；
// Ingredients 与 recipe 同生命周期，整体替换（PUT）或一并创建（POST）。
type RecipeInput struct {
	ID          *string                  `json:"id,omitempty"` // POST 时留空；PUT 时必填
	Name        string                   `json:"name"`
	Emoji       string                   `json:"emoji"`
	Difficulty  string                   `json:"difficulty"`
	Minutes     int                      `json:"minutes"`
	Category    string                   `json:"category"`
	Steps       string                   `json:"steps"`
	Tips        string                   `json:"tips"`
	// 图片图标（base64 编码的 JPEG bytes）。前端把 <input type=file> 选中的图片读成
	// DataURL 后剥离前缀得到纯 base64；nil = 不设置图标。
	IconImageBase64 *string `json:"iconImageBase64,omitempty"`
	// 旧版多行文本食材（兼容历史数据；新表单请用 Ingredients）
	IngredientsLegacyRaw string                 `json:"ingredientsLegacyRaw"`
	Ingredients          []RecipeIngredientInput `json:"ingredients"`
}

type RecipeIngredientInput struct {
	ID     *string `json:"id,omitempty"` // POST 留空；PUT 时如带 id 则保留，否则新建
	Name   string  `json:"name"`
	Amount string  `json:"amount"`
	Order  int     `json:"order"`
}

// List 返回该 device 下所有菜谱（含 ingredients）。
// cook_recipe 表无 created_at，按 name 排序展示。
func (s *RecipeService) List(deviceID string) ([]dto.SyncRecipeDTO, error) {
	var recipes []model.Recipe
	if err := s.db.Where("device_id = ?", deviceID).Order("name asc").Find(&recipes).Error; err != nil {
		return nil, err
	}
	var ings []model.CookIngredient
	if err := s.db.Where("device_id = ?", deviceID).Order("order_idx asc").Find(&ings).Error; err != nil {
		return nil, err
	}
	byRecipe := make(map[string][]dto.SyncIngredientDTO, len(recipes))
	for _, ing := range ings {
		byRecipe[ing.RecipeID] = append(byRecipe[ing.RecipeID], dto.SyncIngredientDTO{
			ID: ing.ID, Name: ing.Name, Amount: ing.Amount, Order: ing.OrderIdx,
		})
	}
	out := make([]dto.SyncRecipeDTO, 0, len(recipes))
	for _, r := range recipes {
		ings := byRecipe[r.ID]
		if ings == nil {
			ings = []dto.SyncIngredientDTO{}
		}
		out = append(out, dto.SyncRecipeDTO{
			ID: r.ID, Name: r.Name, Emoji: r.Emoji, Difficulty: r.Difficulty,
			Minutes: r.Minutes, Category: r.Category,
			IngredientsLegacyRaw: r.IngredientsLegacyRaw,
			Ingredients:          ings,
			Steps:                r.Steps, Tips: r.Tips,
			IconImageBase64: r.IconImageBase64,
		})
	}
	return out, nil
}

// Get 取单个菜谱（含 ingredients）。
func (s *RecipeService) Get(deviceID, id string) (*dto.SyncRecipeDTO, error) {
	var r model.Recipe
	if err := s.db.Where("device_id = ? AND id = ?", deviceID, id).First(&r).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrRecipeNotFound
		}
		return nil, err
	}
	var ings []model.CookIngredient
	if err := s.db.Where("device_id = ? AND recipe_id = ?", deviceID, id).
		Order("order_idx asc").Find(&ings).Error; err != nil {
		return nil, err
	}
	ingDTOs := make([]dto.SyncIngredientDTO, 0, len(ings))
	for _, ing := range ings {
		ingDTOs = append(ingDTOs, dto.SyncIngredientDTO{
			ID: ing.ID, Name: ing.Name, Amount: ing.Amount, Order: ing.OrderIdx,
		})
	}
	return &dto.SyncRecipeDTO{
		ID: r.ID, Name: r.Name, Emoji: r.Emoji, Difficulty: r.Difficulty,
		Minutes: r.Minutes, Category: r.Category,
		IngredientsLegacyRaw: r.IngredientsLegacyRaw,
		Ingredients:          ingDTOs,
		Steps:                r.Steps, Tips: r.Tips,
		IconImageBase64: r.IconImageBase64,
	}, nil
}

// Create 新建菜谱 + 食材子项。同一个事务，失败一起回滚。
func (s *RecipeService) Create(deviceID string, in *RecipeInput) (string, error) {
	recipeID := newUUID()
	r := model.Recipe{
		DeviceID: deviceID, ID: recipeID,
		Name: in.Name, Emoji: in.Emoji, Difficulty: in.Difficulty,
		Minutes: in.Minutes, Category: in.Category,
		IngredientsLegacyRaw: in.IngredientsLegacyRaw,
		Steps: in.Steps, Tips: in.Tips,
		IconImageBase64: in.IconImageBase64,
	}
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&r).Error; err != nil {
			return err
		}
		if err := insertIngredients(tx, deviceID, recipeID, in.Ingredients); err != nil {
			return err
		}
		return upsertSyncMeta(tx, deviceID)
	})
	if err != nil {
		return "", err
	}
	return recipeID, nil
}

// Update 全量更新 recipe + 替换其 ingredients。
// ingredients 替换语义：先 DELETE 旧 ingredients → 再 INSERT 新的（与 iOS
// CookRecipe.ingredients cascade deleteRule 一致）。
func (s *RecipeService) Update(deviceID, id string, in *RecipeInput) error {
	if in.ID == nil || *in.ID != id {
		return ErrRecipeIDMismatch
	}
	// 显式检查存在性，便于返回 404 而不是 silent no-op
	var exists model.Recipe
	if err := s.db.Where("device_id = ? AND id = ?", deviceID, id).First(&exists).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrRecipeNotFound
		}
		return err
	}
	err := s.db.Transaction(func(tx *gorm.DB) error {
		updates := map[string]any{
			"name":                   in.Name,
			"emoji":                  in.Emoji,
			"difficulty":             in.Difficulty,
			"minutes":                in.Minutes,
			"category":               in.Category,
			"ingredients_legacy_raw": in.IngredientsLegacyRaw,
			"steps":                  in.Steps,
			"tips":                   in.Tips,
			"icon_image_base64":      in.IconImageBase64,
		}
		if err := tx.Model(&model.Recipe{}).
			Where("device_id = ? AND id = ?", deviceID, id).
			Updates(updates).Error; err != nil {
			return err
		}
		// 替换 ingredients
		if err := tx.Where("device_id = ? AND recipe_id = ?", deviceID, id).
			Delete(&model.CookIngredient{}).Error; err != nil {
			return err
		}
		if err := insertIngredients(tx, deviceID, id, in.Ingredients); err != nil {
			return err
		}
		return upsertSyncMeta(tx, deviceID)
	})
	return err
}

// Delete 删除 recipe + 其关联 ingredients（ingredients 在事务里显式删除，
// 不依赖外键 cascade；与 clearDevice 全表清空语义一致）。
func (s *RecipeService) Delete(deviceID, id string) error {
	var exists model.Recipe
	if err := s.db.Where("device_id = ? AND id = ?", deviceID, id).First(&exists).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrRecipeNotFound
		}
		return err
	}
	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("device_id = ? AND recipe_id = ?", deviceID, id).
			Delete(&model.CookIngredient{}).Error; err != nil {
			return err
		}
		if err := tx.Where("device_id = ? AND id = ?", deviceID, id).
			Delete(&model.Recipe{}).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx, deviceID)
	})
}

// ---------- 内部辅助 ----------

func insertIngredients(tx *gorm.DB, deviceID, recipeID string, ins []RecipeIngredientInput) error {
	if len(ins) == 0 {
		return nil
	}
	rows := make([]model.CookIngredient, 0, len(ins))
	for _, in := range ins {
		ingID := newUUID()
		if in.ID != nil && *in.ID != "" {
			// PUT 时客户端若带 id，则保留原 id（保证幂等性 / 同步回 iOS 时不产生新 UUID）
			ingID = *in.ID
		}
		rows = append(rows, model.CookIngredient{
			DeviceID: deviceID, ID: ingID,
			RecipeID: recipeID, Name: in.Name, Amount: in.Amount,
			OrderIdx: in.Order,
		})
	}
	return tx.CreateInBatches(rows, 200).Error
}

// upsertSyncMeta 确保 sync_meta 行存在并刷新时间戳；这样 iOS 客户端即使
// 从未上传过，也能直接 download 到 Web 表单录入的数据。
func upsertSyncMeta(tx *gorm.DB, deviceID string) error {
	now := time.Now().Unix()
	meta := model.SyncMetaRow{
		DeviceID:      deviceID,
		SyncTimestamp: now,
		AppVersion:    "web-form",
		DataVersion:   currentDataVersion,
		UpdatedAt:     time.Now(),
	}
	// GORM Save 对复合主键 / 单主键都走 upsert 语义
	return tx.Save(&meta).Error
}
